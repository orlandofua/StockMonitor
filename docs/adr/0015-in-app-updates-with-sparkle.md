# 15. In-app updates with Sparkle, hosted in this repository

Date: 2026-11-18

## Status

Accepted. Partly supersedes [0010](0010-distribute-unnotarized-builds-on-github-releases.md) (the "no auto-updater" decision and the private-repository consequence). Builds on [0009](0009-release-on-merge-with-label-driven-semver.md).

The owner confirmed every choice marked **Default** below in review of PR #34 on 2026-11-18.

## Context

ADR 0010 shipped releases as zips on GitHub Releases with no update notice. Users have to watch the Releases page, quit the app, replace it by hand, and pass Gatekeeper again after every release. Releases happen on every merged pull request (0009), so manual updates fall behind quickly.

The repository was made public on 2026-11-18 so that an update feed and its zips can be downloaded by anyone without a GitHub account. This removes the reason 0010 gave for keeping downloads private.

Sparkle is the standard open-source updater for macOS apps distributed outside the App Store. Sparkle 2 checks an RSS feed (the appcast), downloads the update, verifies it with an EdDSA (ed25519) signature, replaces the app, and relaunches it. It can be added as a Swift package, which fits the SwiftPM build in 0002.

Release builds are ad-hoc signed and not notarized (0010). Sparkle's documentation warns that ad-hoc signed apps may fail to load the framework when Library Validation is on, which happens when the app is signed with the Hardened Runtime. `build.sh` currently signs with `codesign --force --sign -` and no `--options runtime`, so Hardened Runtime and Library Validation are off. Whether Sparkle works with this app's bundle has not been tested yet; spike #28 tests it with the signing options `build.sh` actually uses, and also records what happens if Hardened Runtime is turned on later.

`build.sh` puts the semver from the release label (0009) in `CFBundleShortVersionString` and the release workflow's run number in `CFBundleVersion`. Sparkle compares `CFBundleVersion` values to decide whether an update is newer.

## Decision

### Updater

- Use **Sparkle 2**, added as a Swift package and embedded in `Contents/Frameworks` by `build.sh` (#29), with the standard user driver (`SPUStandardUpdaterController`).
- The app gets a **Check for Updates…** menu item and background checks (#30).
- Versioning stays label-driven as in 0009. Each feed item's `sparkle:version` is the build's `CFBundleVersion` (the release run number, which only goes up) and `sparkle:shortVersionString` is the semver tag without the `v`. Sparkle compares `sparkle:version` values, so the order of updates always follows release order.

### Hosting and feed URL

- **Default:** the feed is served by **GitHub Pages from this repository**:
  `SUFeedURL` = `https://orlandofua.github.io/StockMonitor/appcast.xml`
- The release workflow keeps `appcast.xml` on a `gh-pages` branch and commits the new entry there in the same run that publishes the release (#31).
- Update zips are the existing **GitHub Release assets**: each feed item's enclosure points at `https://github.com/orlandofua/StockMonitor/releases/download/vX.Y.Z/StockMonitor-vX.Y.Z.zip`. No zips are stored in Pages or in git.
- There is no separate releases repository.

Option considered: attach `appcast.xml` to each release and point `SUFeedURL` at `https://github.com/orlandofua/StockMonitor/releases/latest/download/appcast.xml`. It needs no Pages setup, and GitHub redirects that URL to the newest release's asset. It was not picked because:

- The feed's location depends on which release GitHub marks as "latest". A pre-release, a draft, or a hand-edited "latest" flag changes or breaks the feed for every installed copy.
- Pulling a bad release means editing or deleting assets on old releases, which leaves no history. On Pages, every feed change is a commit on `gh-pages` that can be reviewed and reverted.
- Each release would have to re-upload the full feed with all earlier entries.

Pages adds a short delay. Its CDN can cache the feed for up to about 10 minutes, so a new release or a removed entry reaches clients within minutes rather than at once. That is acceptable for daily checks.

### Signing keys

- Updates are signed with an **EdDSA (ed25519) key** made with Sparkle's `generate_keys`. The **repository owner** generates it on their own Mac.
- The private key is stored as the GitHub Actions secret **`SPARKLE_ED_PRIVATE_KEY`** and used only by the release job, through Sparkle's `sign_update`. It is never committed.
- The owner keeps an **offline backup** of the private key in their password manager. After the backup is checked, the copy in the login keychain can be deleted.
- The public key is embedded in `Info.plist` as **`SUPublicEDKey`** by `build.sh`.
- Losing the private key strands every installed copy: those copies only accept updates signed with that key, so their users would have to download a new build by hand. A leaked key lets anyone who can also change the feed, or what a client downloads, push an update that installed copies accept.
- Sparkle accepts a change of EdDSA key only when the update's Apple code signing identity matches the installed app's, and an ad-hoc signature is different for every build. Until Developer ID signing (#12) lands, the key therefore **cannot be rotated** through an update. If it leaks or is lost, the owner removes the secret, generates a new key, ships a release with the new `SUPublicEDKey`, and users must install that release by hand. After #12, a key can be rotated through a normal update as Sparkle documents.

### Install behavior

- **Default:** Sparkle's **standard prompt**. When an update is found, the app shows the version and release notes, and the user picks Install, Skip This Version, or Remind Me Later.
- Users can opt in to **"Install updates automatically"**. Sparkle then downloads updates in the background and installs them when the app quits or relaunches, without a prompt. `SUAllowsAutomaticUpdates` is `YES` and `SUAutomaticallyUpdate` is `NO` by default.
- Updates are installed on quit or relaunch, never while the app is running without the user's knowledge.

### Check frequency

- **Default:** check once a day in the background: `SUEnableAutomaticChecks` = `YES` and `SUScheduledCheckInterval` = `86400`. Setting `SUEnableAutomaticChecks` skips Sparkle's "check automatically?" question on the second launch. Users can turn background checks off. **Check for Updates…** always works.
- A check fetches one small file from GitHub Pages. It does not touch Yahoo (0003), so it does not count against Yahoo's rate limits.

### Apple Developer Program and #12

- **Default:** Sparkle does **not wait** for Developer ID signing and notarization. It ships on the current ad-hoc signing plus EdDSA, **if spike #28 passes**. The EdDSA signature, not the code signature, is what proves an update came from the release job.
- If #28 shows Sparkle cannot load or install updates on an ad-hoc signed app on a supported macOS version, the rollout (#29 to #32) stops, and #12 (Developer ID and notarization) becomes a prerequisite. That would need a new or amended ADR.
- #12 is revisited after Sparkle ships. **Assumption, not yet verified:** when #12 lands, Sparkle keeps working, because the EdDSA key stays the same and the update is still signed with it. Sparkle documents changing the code-signing certificate only for apps that are already Developer ID signed, not a move from ad-hoc to Developer ID. #12 must test this update path (an ad-hoc installed copy updating to a Developer ID signed release) before it ships.

### Intel support

- **Default:** a universal binary is **not needed from day one**. Releases stay arm64-only (0010), and #33 (universal binary) stays deferred at P3. Intel Macs cannot run the downloaded build, so they have nothing to update. When #33 lands, the embedded Sparkle framework must be universal too, and from then on Intel copies receive updates through the same feed.

### Release cadence and channels

- **Default:** **every merged release goes into the feed**, as soon as its release run finishes. Patches are not batched. A merge labeled `skip-release` makes no release and leaves the feed unchanged.
- There is **no beta channel** for now. A channel can be added later with Sparkle's `sparkle:channel` element without changing the feed URL.
- Each feed item sets `sparkle:minimumSystemVersion` to `13.0.0`, matching `LSMinimumSystemVersion`, and links to the GitHub release page for its notes.

### Bad-release recovery

- There is **no automatic rollback**. Sparkle does not downgrade, and the app keeps no previous copy.
- To pull a bad release: remove its item from `appcast.xml` on `gh-pages` (a revertable commit). Copies that have not installed it stop being offered it once the Pages cache expires.
- Then ship a fixed release through the normal merge flow. It gets a higher `CFBundleVersion` and semver, so copies that already installed the bad release update to it.
- The bad GitHub Release can stay as it is or be marked as a pre-release. Deleting its zip breaks only downloads of that version.
- If the bad release breaks the updater itself, its users must download the fix by hand. The README (#32) explains how.

### Gatekeeper and ad-hoc signing risk

- The first install still goes past Gatekeeper by hand as in 0010. The aim is that updates installed by Sparkle need no further Gatekeeper step. This, and whether library validation lets an ad-hoc signed app load an ad-hoc signed Sparkle framework, was tested by spike #28. Its findings and the macOS versions it could and could not cover are in the section below.
- Sparkle cannot update an app that macOS runs from a translocated (read-only) location, such as straight from Downloads. The README keeps telling users to move the app to `/Applications` first.

### Spike findings (#28)

Recorded on 2026-11-18 with Sparkle 2.10.1.

**Result: go.** Sparkle 2 loads in, and updates, an app built with SwiftPM and signed exactly as `build.sh` signs it today (`codesign --force --sign -`, no Hardened Runtime). The rollout (#29 to #32) continues on ad-hoc signing. #12 is not a prerequisite. Hardened Runtime must stay off until #12 lands (see below).

#### How it was tested

`scripts/spike/sparkle-28/run.sh` reproduces every result below. It builds a stand-in app, `SparkleSpike`, in a temporary folder. The app is a SwiftPM executable with the same `Info.plist` keys as `build.sh`, including `LSUIElement` and `LSMinimumSystemVersion` 13.0. It embeds `Sparkle.framework` in `Contents/Frameworks` and starts an `SPUUpdater`. The script never touches `build/`, `.build/`, the real app, or any keychain. It keeps SwiftPM's download cache and temporary files inside its work folder, and at the end it deletes that folder, the test keys, and the spike's preferences and caches. It refuses a `SPIKE_WORK` folder whose name does not start with `sparkle-spike`, because it deletes that folder, and it stops if the HTTP port is already in use. On a Mac with SIP on, a Hardened Runtime build that unexpectedly loads the framework counts as a failure.

```sh
scripts/spike/sparkle-28/run.sh all         # or: update | quarantine | negative | hardened
SPIKE_KEEP=1 scripts/spike/sparkle-28/run.sh update   # keep the work folder (and results.txt) to inspect it
SPIKE_PORT=8800 scripts/spike/sparkle-28/run.sh all   # if port 8765 is taken
```

The script does the following steps:

1. Builds the package with `swift build -c release`. Sparkle comes from SwiftPM (`.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")`).
2. Makes a throwaway ed25519 key pair with `make-test-key.swift` (CryptoKit). The private key is the base64 32-byte seed, the same format `generate_keys -x` exports. `generate_keys` itself was not used, because it always stores the key in the login keychain. `sign_update --ed-key-file` accepts this key, and Sparkle verifies its signatures.
3. Builds v0.0.1 (`CFBundleVersion` 1) and v0.0.2 (`CFBundleVersion` 2) with `SUFeedURL` = `http://127.0.0.1:8765/appcast.xml` and `SUPublicEDKey` set to the test public key. The framework is copied with `ditto`, and then the bundle is signed once with `codesign --force --sign - SparkleSpike.app`.
4. Zips v0.0.2 with `ditto -c -k --sequesterRsrc --keepParent`, as the release workflow does. It signs the zip with `sign_update --ed-key-file private.seed -p`, writes `appcast.xml`, and serves both with `python3 -m http.server 8765 --bind 127.0.0.1`.
5. Unzips v0.0.1 into an install folder and starts it with `open`. A spike-only user driver answers "install" to every Sparkle prompt, so the full check, download, verify, install and relaunch path runs without clicks. Sparkle's standard user driver (`SPUStandardUpdaterController`, #30) was not exercised. It uses the same downloader and installer.

#### Results

| Scenario | macOS 27.0.1 (26A434), this Mac, SIP on | macOS 15.8.2 (24H232), GitHub `macos-15`, SIP off | macOS 26.7.2 (25G332), GitHub `macos-26`, SIP off |
| --- | --- | --- | --- |
| Signed like `build.sh`: framework loads, v0.0.1 updates and relaunches as v0.0.2 | Pass | Pass | Pass |
| Same, after a download with `com.apple.quarantine` set (first launch bypassed with `xattr -dr`) | Pass | Pass | Pass |
| EdDSA signature changed by one character | Rejected | Rejected | Rejected |
| No EdDSA signature in the feed | Rejected | Rejected | Rejected |
| Zip replaced after signing (valid signature of the original zip) | Rejected | Rejected | Rejected |
| One byte of the signed zip flipped | Rejected | Rejected | Rejected |
| Hardened Runtime on (`--options runtime`), ad hoc | Framework does not load | Loads (SIP off, not meaningful) | Loads (SIP off, not meaningful) |
| Hardened Runtime + `com.apple.security.cs.disable-library-validation` | Pass | Pass | Pass |

What "Pass" means. Sparkle found v0.0.2 and downloaded it, and EdDSA validation passed. Sparkle quit v0.0.1, replaced the bundle in place, and relaunched it within about one second. Afterwards:

- the installed `CFBundleVersion` is 2;
- the relaunched process reports version 2;
- the updated bundle passes `codesign --verify --deep --strict`;
- no file in the updated bundle has `com.apple.quarantine` (only `com.apple.provenance`).

No Gatekeeper prompt appeared on the relaunch. `spctl --assess --type execute` rejects every ad-hoc bundle, before and after the update. That is expected for an un-notarized app and does not block launching a bundle without the quarantine attribute.

What "Rejected" means. Sparkle reported `SUSparkleErrorDomain` 4005 ("The update is improperly signed and could not be validated"), with an underlying 3002 error naming the EdDSA mismatch or the missing signature. v0.0.2 never ran, the installed `CFBundleVersion` stayed 1, and v0.0.1 kept running.

#### Details for #29

- **Framework signature.** The `Sparkle.framework` in Sparkle's SwiftPM artifact is already ad-hoc signed, with the runtime flag set (`flags=0x10002(adhoc,runtime)`). Copy it with `ditto`, which keeps the `Versions/Current` symlinks, and then sign the app bundle once with the existing `codesign --force --sign -`. `--deep` and re-signing the framework are not needed. The result passes `codesign --verify --deep --strict`.
- **rpath.** SwiftPM does not add `@executable_path/../Frameworks`. Without it the binary cannot find the framework. The spike passes `-Xlinker -rpath -Xlinker @executable_path/../Frameworks` through `linkerSettings: [.unsafeFlags(...)]`. That is allowed in a root package. The same flags can be passed to `swift build` in `build.sh` instead.
- **Silent signing failures.** `build.sh` runs `codesign ... >/dev/null 2>&1 || true`, so a signing failure is hidden. Once the bundle contains a framework, a bad signature breaks updates. #29 should let `codesign` fail the build and add `codesign --verify --deep --strict`.
- **Tools.** `sign_update` and `generate_keys` ship in the same SwiftPM artifact (`.build/artifacts/sparkle/Sparkle/bin`). The release job (#31) needs no separate download. `sign_update --ed-key-file -` reads the key from standard input, which suits a GitHub secret.
- **Feed URL.** An `http://127.0.0.1` feed worked for the spike. Production uses the HTTPS Pages URL above.

#### Hardened Runtime

On macOS 27.0.1 with SIP on, an ad-hoc app signed with `--options runtime` does not start. dyld refuses the embedded framework: "mapping process and mapped file (non-platform) have different Team IDs". Ad-hoc code has no Team ID, so Library Validation always fails. Adding the `com.apple.security.cs.disable-library-validation` entitlement fixes the load, and updates then work. The hosted runners run with SIP disabled, where Library Validation is not enforced, so their "loads" result says nothing about real Macs. Decision: keep `build.sh` without `--options runtime`. If Hardened Runtime is wanted before #12, it needs that entitlement. With Developer ID (#12) the app and the re-signed framework share a Team ID, so the entitlement is not needed.

#### Not covered

- **macOS 13 and 14 were not tested.** No Mac with those versions was available. GitHub no longer offers `macos-13` and `macos-14` runners: `macos-14` failed with "The configuration 'macos-14-arm64-us-default' is not supported", and `macos-13` never got a runner. Nothing found suggests they behave differently, because the passing path uses no Hardened Runtime and therefore no Library Validation. This is an assumption.
- **macOS 15 was tested only on a hosted runner with SIP disabled.** The update mechanics and EdDSA checks are covered there. Gatekeeper and code-signing enforcement on a normal macOS 15 Mac are not.
- **First launch through "Open Anyway"** in System Settings was not tested, because it needs a click. That path keeps the quarantine attribute on the installed copy, with the user's approval recorded. The spike only covered the `xattr -dr` bypass. In every run the updated bundle had no quarantine attribute, so the result should not depend on how the first launch was approved. This needs a manual check.
- **Sparkle's standard update window** and the opt-in automatic install were not exercised. They belong to #30.

To fill these gaps, the owner can run `scripts/spike/sparkle-28/run.sh all` on any Mac running macOS 13, 14 or 15 with SIP on, and expect `== Done: 0 failure(s)`. On one of them, also do the manual "Open Anyway" check:

1. Run `SPIKE_KEEP=1 scripts/spike/sparkle-28/run.sh update` once, to get a work folder with the test key and the server.
2. Stop it, then serve the work folder's `www` again with `python3 -m http.server 8765 --bind 127.0.0.1`.
3. Copy `v1.zip` to `~/Downloads` through a browser, or tag it with `xattr -w com.apple.quarantine "0083;$(printf %x $(date +%s));Safari;"`, and unzip it in Finder into `/Applications`.
4. Open v0.0.1 and approve it with Open Anyway.
5. Confirm it updates to v0.0.2 and relaunches with no further Gatekeeper prompt.
6. Clean up: delete `/Applications/SparkleSpike.app`, stop the server, and delete the work folder. Then run `defaults delete com.local.SparkleSpike28` and delete `~/Library/Preferences/com.local.SparkleSpike28.plist` and `~/Library/Caches/com.local.SparkleSpike28`.

## Consequences

- Users get an update prompt within a day of each release, and one click installs it. Settings survive updates because they live in `UserDefaults` (0007).
- The app makes one extra network request a day, to GitHub Pages, and depends on Sparkle as a third-party framework. Sparkle's updates must be followed.
- The release workflow gains an EdDSA signing step, a secret, and a push to `gh-pages`. A release with a missing or broken feed entry must fail rather than publish (#31).
- Release downloads and the feed are public. Anyone can download a build without a GitHub account. The README's note that the repository is private becomes wrong and is updated with #32.
- The EdDSA private key is a single point of failure. Losing it strands installed copies, and the backup is the owner's responsibility. With ad-hoc signing it cannot be rotated through an update.
- Every merged release reaches users quickly, so a bad merge spreads fast. Recovery is to remove the feed entry and ship a fix.
- The plan depended on spike #28, which passed on ad-hoc signing without Hardened Runtime. Turning on Hardened Runtime before Developer ID (#12) would break loading the framework unless library validation is disabled by entitlement.
- Rollout follows these issues: #28 (spike), #29 (embed Sparkle), #30 (menu item and daily checks), #31 (sign and publish the feed), #32 (user docs), and later #33 (Intel).
