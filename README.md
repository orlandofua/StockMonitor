# StockMonitor

[![CI](https://github.com/orlandofua/StockMonitor/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/orlandofua/StockMonitor/actions/workflows/ci.yml)

A lightweight macOS menu bar app that shows live prices for the stocks, futures, and crypto you choose, in a compact two-line style:

```
BZ=F
92.16 [-0.28]
```

Each symbol gets its own menu bar item, with a green or red badge for the daily change against the previous close, or for the change over a longer period that you pick per symbol. Prices stream live over Yahoo Finance's WebSocket when the symbol supports it, and fall back to polling Yahoo's chart endpoint when it does not.

After the Mac wakes from sleep, or when the network connection comes back, every symbol is polled again within a few seconds, so prices that do not stream do not sit at their old value until the next scheduled poll.

If a symbol stops updating (no live stream and no successful poll for twice the polling interval, or 5 minutes, whichever is longer), its ticker turns gray as soon as that time passes and its menu shows "Stale: last update …" with the last error, such as "timeout" or "offline". It returns to normal with the next successful update.

## Install

Requirements: macOS 13 (Ventura) or later on a Mac with Apple silicon (M1 or newer). Release builds are arm64 only and do not run on Intel Macs; on an Intel Mac, [build from source](#build-and-run) instead.

1. Open the [latest release](https://github.com/orlandofua/StockMonitor/releases/latest) and download `StockMonitor-vX.Y.Z.zip` from its Assets list.
2. Optional: check the download against the `.sha256` file from the same release. Run this in the folder that holds both files. It prints `OK` when the zip is intact:

   ```sh
   shasum -a 256 -c StockMonitor-vX.Y.Z.zip.sha256
   ```

   Safari unzips downloads and deletes the zip by default ("Open safe files after downloading" in Safari > Settings > General), which leaves nothing to check. To keep the zip, turn that setting off, use another browser, or download both files with the GitHub CLI:

   ```sh
   gh release download --repo orlandofua/StockMonitor --pattern 'StockMonitor-*.zip*'
   ```

3. Double-click the zip to unzip it, then drag `StockMonitor.app` into `/Applications`. Safari may unzip the file for you, in which case `StockMonitor.app` is already in Downloads.
4. Open the app once past Gatekeeper, using one of the options below.

The app is ad-hoc signed and not notarized by Apple, so the first launch is blocked with a message such as "Apple could not verify “StockMonitor” is free of malware" (macOS 15 and later) or "“StockMonitor” can’t be opened because Apple cannot check it for malicious software" (macOS 13 and 14). This happens only once per downloaded copy. Pick one way to allow it:

- **System Settings (any macOS 13+):** double-click `StockMonitor.app` and close the warning with **Done** or **OK**. Open **System Settings > Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to the message about StockMonitor. Confirm with **Open Anyway** (or **Open**) and your password or Touch ID. The button appears for about an hour after the blocked launch.
- **Right-click (macOS 13 and 14 only):** Control-click or right-click `StockMonitor.app` in Finder, choose **Open**, then click **Open** in the dialog. macOS 15 removed this shortcut, so on macOS 15 and later use one of the other options.
- **Terminal (any macOS 13+):** remove the quarantine attribute that the browser added, then open the app:

  ```sh
  xattr -dr com.apple.quarantine /Applications/StockMonitor.app
  open /Applications/StockMonitor.app
  ```

StockMonitor is a menu bar app with no Dock icon or window. After it opens, look for the ticker (`BZ=F` by default) at the right side of the menu bar.

Releases after v1.3.0 update themselves from inside the app, without another Gatekeeper step (see [Updates](#updates)). Releases up to v1.3.0 have no updater, so move from those to a newer release [by hand](#update-by-hand) once.

Developer ID signing and notarization, which would remove the Gatekeeper step, are planned in [#12](https://github.com/orlandofua/StockMonitor/issues/12) and not done yet. See [ADR 0010](docs/adr/0010-distribute-unnotarized-builds-on-github-releases.md).

## Build and run

Requires macOS 13+ and Swift 5.10+ (the Command Line Tools are enough; Xcode is not required).

```sh
./build.sh
open build/StockMonitor.app
```

Run the unit tests with `./test.sh`.

The app bundle embeds [Sparkle](https://sparkle-project.org) in `Contents/Frameworks` for in-app updates (see [ADR 0015](docs/adr/0015-in-app-updates-with-sparkle.md)). SwiftPM downloads it on the first build. A local build has no update feed and never checks for updates. To build one that does, set both the feed URL and the EdDSA public key:

```sh
SPARKLE_FEED_URL=https://orlandofua.github.io/StockMonitor/appcast.xml \
SPARKLE_PUBLIC_ED_KEY=<base64 public key> ./build.sh
```

`./build.sh` fails if the feed URL is set without a valid key, and it fails if the signed bundle does not pass `codesign --verify --deep --strict`.

Every pull request and every push to `main` runs `./test.sh` and then `./build.sh` on GitHub Actions (`.github/workflows/ci.yml`).

Commit messages and pull request titles follow [Conventional Commits](CONTRIBUTING.md#commit-messages), checked on every pull request by `.github/workflows/commit-lint.yml`. Run `scripts/install-hooks.sh` once to check them locally as you commit.

## Releases

Versions are semver tags (`vMAJOR.MINOR.PATCH`) created by `.github/workflows/release.yml` when a pull request is merged into `main`. Each release has two assets: `StockMonitor-vX.Y.Z.zip`, the zipped `StockMonitor.app`, and `StockMonitor-vX.Y.Z.zip.sha256`, its SHA-256 checksum. The pull request's label picks the bump:

| Label | Effect |
| --- | --- |
| `release:patch` or no release label | `v1.2.3` to `v1.2.4` |
| `release:minor` | `v1.2.3` to `v1.3.0` |
| `release:major` | `v1.2.3` to `v2.0.0` |
| `skip-release` | no release |

See [CONTRIBUTING.md](CONTRIBUTING.md#release-labels) for which label to pick. Local builds default to version `1.0`. Set `VERSION=1.2.3 ./build.sh` to stamp a specific version.

### Update feed

The same release run publishes the update feed for in-app updates ([ADR 0015](docs/adr/0015-in-app-updates-with-sparkle.md)). It builds the app with `SUFeedURL` set to `https://orlandofua.github.io/StockMonitor/appcast.xml`, signs the zip with Sparkle's `sign_update` and the EdDSA private key, checks the signature against the `SUPublicEDKey` in the built app, and adds an item to `appcast.xml` on the `gh-pages` branch, which GitHub Pages serves. The item has the version, the build number (`sparkle:version`), the zip's size and signature, a minimum macOS of 13.0.0, and a link to the GitHub release page. The zip itself stays a release asset.

The release is uploaded as a draft first, then the feed commit is pushed, then the release is published. If any step fails, the run fails, and nothing is published or the release is left as a draft. To retry, delete the draft release (if there is one) and re-run the workflow. A `skip-release` merge makes no release and does not touch the feed. The first release creates the `gh-pages` branch.

The workflow needs this setup in the repository settings. Without it, every release run fails in its first step.

| Name | Kind | Value |
| --- | --- | --- |
| `SPARKLE_ED_PRIVATE_KEY` | Actions secret | The EdDSA private key (base64), as exported by `generate_keys -x` |
| `SPARKLE_PUBLIC_ED_KEY` | Actions variable | The matching public key (base64, 44 characters), printed by `generate_keys -p` |

One-time setup by the repository owner, on their own Mac:

1. Run `./build.sh` once so SwiftPM downloads Sparkle, then `.build/artifacts/sparkle/Sparkle/bin/generate_keys`. It creates the key pair in the login keychain and prints the public key.
2. Export the private key with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x private-key.txt`, store it as the secret with `gh secret set SPARKLE_ED_PRIVATE_KEY < private-key.txt`, back it up offline as [CONTRIBUTING.md](CONTRIBUTING.md#back-up-the-signing-key) describes, and then delete `private-key.txt`. Never commit it.
3. Store the public key with `gh variable set SPARKLE_PUBLIC_ED_KEY --body '<public key>'`.
4. After the first release has created the `gh-pages` branch, turn on GitHub Pages under Settings > Pages: Deploy from a branch, `gh-pages`, `/ (root)`. Check that the feed loads with `curl -fsS https://orlandofua.github.io/StockMonitor/appcast.xml`.

To pull a bad release from the feed, or to back up or replace the signing key, see [Update feed and signing key](CONTRIBUTING.md#update-feed-and-signing-key) in CONTRIBUTING.md.

## Usage

Click any ticker in the menu bar to:

- See the full name, price, change, previous close, and last update time, plus the last error when a poll failed
- Refresh now (⌘R)
- Add a symbol (⌘N), using any Yahoo Finance ticker such as `AAPL`, `BZ=F`, `BTC-USD`, or `^GSPC`. The ticker is checked with Yahoo first: an unknown one shows "Symbol not found" and a network problem shows its own message, and the dialog stays open so you can fix it or cancel
- Remove the symbol
- Toggle between point and percent change
- Pick what the change is measured from under **Compare To** (see below)
- See whether the symbol is streaming live or being polled
- Set the polling interval (15s, 30s, 1m, or 5m)
- Turn **Launch at Login** on or off
- **Check for Updates…** and turn **Install Updates Automatically** on or off (only in builds with an update feed, see below)

Symbols and settings persist between launches.

### Compare to a longer period

Each ticker's **Compare To** submenu sets what its change is measured from: **1D** (the previous close, the default), or the close **1W**, **1M**, **3M**, **6M**, or **1Y** ago. Each symbol keeps its own choice across launches.

For any period other than 1D, the ticker shows an outlined pill with the period next to the change, for example `186.52 [+4.12] 1M`, and the menu shows the period change, the close it is measured from ("Close on Oct 17 182.40"), and today's change. Periods are counted in calendar days; when that day has no close, such as a weekend or holiday, the close before it is used. If the symbol has less history than the period, the earliest close is used and marked "earliest available". The history is fetched once when you pick the period and again once a day, not on every poll. Until it arrives the ticker shows the daily change without the pill.

### Start at login

Choose **Launch at Login** in any ticker menu. A checkmark means StockMonitor opens when you log in. The menu reads the setting from macOS each time it opens, so it also reflects changes made in System Settings › General › Login Items. If macOS asks you to approve the login item, the box shows a dash and clicking it opens Login Items, where you can allow StockMonitor. If macOS refuses the change, an alert says why.

Move `StockMonitor.app` to `/Applications` before turning this on, because the login item points at the copy of the app you turned it on from. You can still add the app by hand under System Settings › General › Login Items.

### Updates

StockMonitor updates itself with [Sparkle](https://sparkle-project.org) ([ADR 0015](docs/adr/0015-in-app-updates-with-sparkle.md)). Every merged release goes into the update feed as soon as it is published, so updates can arrive often.

- **Daily check.** StockMonitor checks for a new version in the background once a day. The check downloads one small file from GitHub Pages and does not touch Yahoo Finance.
- **Check for Updates…** in any ticker menu checks right away. It either says you are up to date or shows the new version with its release notes.
- **Prompt (the default).** When an update is found, a window shows the new version and its release notes. Choose **Install Update** to download and install it now (StockMonitor relaunches), **Skip This Version** to not be offered that version again, or **Remind Me Later**.
- **Install Updates Automatically.** Turn this on in any ticker menu to have updates downloaded in the background and installed the next time StockMonitor quits or relaunches, with no prompt. A checkmark means it is on. It is off by default, and the setting is kept across launches and updates.

To turn off automatic install, open any ticker menu and choose **Install Updates Automatically** so that the checkmark goes away. Updates are then offered in the prompt again.

To turn off the daily background check as well, quit StockMonitor and run the command below. **Check for Updates…** keeps working. To turn the daily check back on, run it again with `true`.

```sh
defaults write com.local.StockMonitor SUEnableAutomaticChecks -bool false
```

Updates are signed. Before installing, StockMonitor checks the download against a public key built into the app, and refuses any update that the release workflow did not sign. Updates installed this way do not need another Gatekeeper step, and your symbols and settings are kept.

Updates need the app in a folder you can write to, such as `/Applications`. If you open it straight from Downloads or from the zip, macOS runs it from a read-only location and the update fails, so move it to `/Applications` first.

Update checks exist only in builds made with both `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY` set (see [Build and run](#build-and-run)). Releases made by the release workflow set both. Releases up to v1.3.0 and a plain `./build.sh` do not, so they show no update items and never check for updates.

### Update by hand

Install a new release by hand when you run v1.3.0 or older, when **Check for Updates…** reports an error such as "The update is improperly signed and could not be validated", or when the release notes ask you to.

1. Quit StockMonitor from any of its menus.
2. Download the new release as in [Install](#install), steps 1 to 3, and replace `StockMonitor.app` in `/Applications` with it.
3. Open it past Gatekeeper again, as in [Install](#install), step 4.

Your symbols and settings are kept.

## Architecture

Design decisions are recorded as ADRs in [`docs/adr`](docs/adr/README.md).
