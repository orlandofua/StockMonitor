# 17. Developer ID signing and notarization for releases

Date: 2026-11-20

## Status

Accepted. Supersedes the signing parts of [0002](0002-native-appkit-with-swift-package-manager.md) and [0010](0010-distribute-unnotarized-builds-on-github-releases.md).

## Context

ADR 0002 ad-hoc signs the app and notes that distributing it to other machines needs a Developer ID signature and notarization. ADR 0010 shipped ad-hoc signed, un-notarized releases anyway and deferred signing to issue #12. Every downloaded copy therefore needs a Gatekeeper workaround on first launch, and users get no malware check from Apple.

Since ADR 0015 the app embeds `Sparkle.framework`, which contains its own code: the `Installer` and `Downloader` XPC services, the `Autoupdate` helper and `Updater.app`. Sparkle's SwiftPM artifact ships these ad-hoc signed. Notarization rejects a bundle in which any code lacks a Developer ID signature, a secure timestamp or the Hardened Runtime. With the Hardened Runtime on, Library Validation also stops the app from loading a framework signed by a different team. So every nested piece has to be re-signed with the same identity, inside out, before the app itself (Sparkle's "Sandboxing and code signing" documentation).

Signing and notarizing need an Apple Developer Program membership ($99 a year), a Developer ID Application certificate and an App Store Connect API key. Whether to pay for the membership is the repository owner's decision, and releases must keep working until it is made.

## Decision

- `scripts/sign-app.sh <app> <identity>` re-signs a bundle made by `build.sh` with the Hardened Runtime and a secure timestamp, in this order: `Installer.xpc`, `Downloader.xpc` (keeping its entitlements), `Autoupdate`, `Updater.app`, `Sparkle.framework`, then `StockMonitor.app`. It ends with `codesign --verify --deep --strict`. The identity `-` signs ad hoc without a timestamp, which lets `scripts/sign-app-tests.sh` check the order, the Hardened Runtime flags and the entitlements without a certificate.
- `build.sh` is unchanged and still produces the ad-hoc app without the Hardened Runtime, for local builds and CI.
- The release workflow turns signing on when all five secrets are set: `DEVELOPER_ID_CERTIFICATE_P12`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `NOTARY_API_KEY_P8`, `NOTARY_API_KEY_ID` and `NOTARY_API_ISSUER_ID`. It then:
  1. imports the certificate into a temporary keychain, deleted at the end of the run,
  2. runs `sign-app.sh` with the certificate's identity,
  3. submits a zip of the app with `xcrun notarytool submit --wait`, prints Apple's log and fails if the status is not `Accepted`,
  4. staples the ticket to the app with `xcrun stapler staple`,
  5. fails unless `spctl --assess --type execute` reports `source=Notarized Developer ID`,
  6. zips the stapled app, and the existing steps sign the zip with EdDSA and publish it (ADR 0015).
- With none of the five secrets set, the workflow ships the ad-hoc build as before and logs a warning. With only some set, it fails before running the tests, so a half-finished setup never ships an ad-hoc build by mistake.
- Notarization uses an App Store Connect API key rather than an Apple ID and app-specific password, because a key can be limited to the Developer role and revoked on its own.
- No certificate or key is stored in the repository. The secrets are documented in the README.

## Consequences

- Once the secrets are set, downloaded releases open without any Gatekeeper workaround, and Apple's malware check covers both the release zips and the zips Sparkle downloads.
- Release runs take longer, because notarization usually takes a few minutes. The job timeout is 45 minutes.
- A release now depends on Apple's notary service. If it is down or rejects the app, the run fails before anything is published, and the merge can be released by re-running the workflow.
- The Developer ID certificate expires after five years and the membership must be renewed every year. An expired membership makes notarization fail, and so the release fails rather than silently shipping an ad-hoc build.
- Updating from an ad-hoc release to the first notarized one goes through Sparkle, which accepts the update because its EdDSA signature is valid. This transition should be checked by hand on the first notarized release. Going back from notarized releases to ad-hoc ones by removing the secrets is not supported: Sparkle may refuse an update whose code signature no longer matches the installed app.
- The ad-hoc fallback stays until the owner sets up the secrets. Until then the README keeps the Gatekeeper steps.
