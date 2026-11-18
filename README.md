# StockMonitor

[![CI](https://github.com/orlandofua/StockMonitor/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/orlandofua/StockMonitor/actions/workflows/ci.yml)

A lightweight macOS menu bar app that shows live prices for the stocks, futures, and crypto you choose, in a compact two-line style:

```
BZ=F
92.16 [-0.28]
```

Each symbol gets its own menu bar item, with a green or red badge for the daily change against the previous close. Prices stream live over Yahoo Finance's WebSocket when the symbol supports it, and fall back to polling Yahoo's chart endpoint when it does not.

After the Mac wakes from sleep, or when the network connection comes back, every symbol is polled again within a few seconds, so prices that do not stream do not sit at their old value until the next scheduled poll.

If a symbol stops updating (no live stream and no successful poll for twice the polling interval, or 5 minutes, whichever is longer), its ticker turns gray as soon as that time passes and its menu shows "Stale: last update …" with the last error, such as "timeout" or "offline". It returns to normal with the next successful update.

## Install

Requirements: macOS 13 (Ventura) or later on a Mac with Apple silicon (M1 or newer). Release builds are arm64 only and do not run on Intel Macs; on an Intel Mac, [build from source](#build-and-run) instead.

The repository is private, so the release links below open only for GitHub accounts with access to it. Sign in to GitHub first; anyone else sees a 404 page.

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

To update, quit StockMonitor from any of its menus, replace `StockMonitor.app` in `/Applications` with the new version, and allow it past Gatekeeper again the same way. Your symbols and settings are kept.

Developer ID signing and notarization, which would remove the Gatekeeper step, are planned in [#12](https://github.com/orlandofua/StockMonitor/issues/12) and not done yet. See [ADR 0010](docs/adr/0010-distribute-unnotarized-builds-on-github-releases.md).

## Build and run

Requires macOS 13+ and Swift 5.10+ (the Command Line Tools are enough; Xcode is not required).

```sh
./build.sh
open build/StockMonitor.app
```

Run the unit tests with `./test.sh`.

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

## Usage

Click any ticker in the menu bar to:

- See the full name, price, change, previous close, and last update time, plus the last error when a poll failed
- Refresh now (⌘R)
- Add a symbol (⌘N), using any Yahoo Finance ticker such as `AAPL`, `BZ=F`, `BTC-USD`, or `^GSPC`. The ticker is checked with Yahoo first: an unknown one shows "Symbol not found" and a network problem shows its own message, and the dialog stays open so you can fix it or cancel
- Remove the symbol
- Toggle between point and percent change
- See whether the symbol is streaming live or being polled
- Set the polling interval (15s, 30s, 1m, or 5m)
- Turn **Launch at Login** on or off

Symbols and settings persist between launches.

### Start at login

Choose **Launch at Login** in any ticker menu. A checkmark means StockMonitor opens when you log in. The menu reads the setting from macOS each time it opens, so it also reflects changes made in System Settings › General › Login Items. If macOS asks you to approve the login item, the box shows a dash and clicking it opens Login Items, where you can allow StockMonitor. If macOS refuses the change, an alert says why.

Move `StockMonitor.app` to `/Applications` before turning this on, because the login item points at the copy of the app you turned it on from. You can still add the app by hand under System Settings › General › Login Items.

## Architecture

Design decisions are recorded as ADRs in [`docs/adr`](docs/adr/README.md).
