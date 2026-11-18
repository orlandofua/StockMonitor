# StockMonitor

[![CI](https://github.com/orlandofua/StockMonitor/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/orlandofua/StockMonitor/actions/workflows/ci.yml)

A lightweight macOS menu bar app that shows live prices for the stocks, futures, and crypto you choose, in a compact two-line style:

```
BZ=F
92.16 [-0.28]
```

Each symbol gets its own menu bar item, with a green or red badge for the daily change against the previous close. Prices stream live over Yahoo Finance's WebSocket when the symbol supports it, and fall back to polling Yahoo's chart endpoint when it does not.

After the Mac wakes from sleep, or when the network connection comes back, every symbol is polled again within a few seconds, so prices that do not stream do not sit at their old value until the next scheduled poll.

## Build and run

Requires macOS 13+ and Swift 5.10+ (the Command Line Tools are enough; Xcode is not required).

```sh
./build.sh
open build/StockMonitor.app
```

Run the unit tests with `./test.sh`.

Every pull request and every push to `main` runs `./test.sh` and then `./build.sh` on GitHub Actions (`.github/workflows/ci.yml`).

## Download

Every merged pull request publishes a [GitHub Release](https://github.com/orlandofua/StockMonitor/releases) with a zipped `StockMonitor.app` and its SHA-256 checksum. The app is not notarized, so remove the quarantine attribute before the first launch:

```sh
unzip StockMonitor-vX.Y.Z.zip
xattr -dr com.apple.quarantine StockMonitor.app
open StockMonitor.app
```

## Releases

Versions are semver tags (`vMAJOR.MINOR.PATCH`) created by `.github/workflows/release.yml` when a pull request is merged into `main`. The pull request's label picks the bump:

| Label | Effect |
| --- | --- |
| `release:patch` or no release label | `v1.2.3` to `v1.2.4` |
| `release:minor` | `v1.2.3` to `v1.3.0` |
| `release:major` | `v1.2.3` to `v2.0.0` |
| `skip-release` | no release |

Local builds default to version `1.0`. Set `VERSION=1.2.3 ./build.sh` to stamp a specific version.

## Usage

Click any ticker in the menu bar to:

- See the full name, price, change, previous close, and last update time
- Refresh now (⌘R)
- Add a symbol (⌘N), using any Yahoo Finance ticker such as `AAPL`, `BZ=F`, `BTC-USD`, or `^GSPC`. The ticker is checked with Yahoo first: an unknown one shows "Symbol not found" and a network problem shows its own message, and the dialog stays open so you can fix it or cancel
- Remove the symbol
- Toggle between point and percent change
- See whether the symbol is streaming live or being polled
- Set the polling interval (15s, 30s, 1m, or 5m)

Symbols and settings persist between launches.

## Architecture

Design decisions are recorded as ADRs in [`docs/adr`](docs/adr/README.md).

To start at login, move `StockMonitor.app` to `/Applications` and add it under System Settings › General › Login Items.
