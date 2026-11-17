# StockMonitor

A lightweight macOS menu bar app that shows live prices for the stocks, futures, and crypto you choose, in a compact two-line style:

```
BZ=F
92.16 [-0.28]
```

Each symbol gets its own menu bar item, with a green or red badge for the daily change against the previous close. Prices stream live over Yahoo Finance's WebSocket when the symbol supports it, and fall back to polling Yahoo's chart endpoint when it does not.

## Build and run

Requires macOS 13+ and Swift 5.10+ (the Command Line Tools are enough; Xcode is not required).

```sh
./build.sh
open build/StockMonitor.app
```

Run the unit tests with `./test.sh`.

## Usage

Click any ticker in the menu bar to:

- See the full name, price, change, previous close, and last update time
- Refresh now (⌘R)
- Add a symbol (⌘N), using any Yahoo Finance ticker such as `AAPL`, `BZ=F`, `BTC-USD`, or `^GSPC`
- Remove the symbol
- Toggle between point and percent change
- See whether the symbol is streaming live or being polled
- Set the polling interval (15s, 30s, 1m, or 5m)

Symbols and settings persist between launches.

## Architecture

Design decisions are recorded as ADRs in [`docs/adr`](docs/adr/README.md).

To start at login, move `StockMonitor.app` to `/Applications` and add it under System Settings › General › Login Items.
