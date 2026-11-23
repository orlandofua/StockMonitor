# StockMonitor

A macOS menu bar app that shows one ticker per tracked symbol, with live prices for stocks, futures and crypto.

## Language

**Symbol**:
A Yahoo Finance instrument the user tracks, such as `AAPL`, `BZ=F` or `BTC-USD`.
_Avoid_: Stock, instrument

**Ticker**:
The menu bar item for one symbol: its price, change badge and menu. In code and ADR 0004, "status item" means the AppKit `NSStatusItem` that draws a ticker; use "ticker" for the domain concept.
_Avoid_: Widget, "status item" for the domain concept

**Ticker state**:
Everything the app knows about one tracked symbol that decides what its ticker and menu show: its quote, last error, freshness, whether it is live, and its baseline.
_Avoid_: Symbol state, quote state

**Tick**:
One price update for a symbol pushed by the stream, stamped with the exchange's time.
_Avoid_: Stream update, push

**Poll**:
One request that fetches a symbol's full quote (price, name, currency and previous close) on the refresh interval, or on demand.
_Avoid_: Fetch, refresh (for a single request)

**Live**:
A symbol whose last tick arrived less than two minutes ago. A live symbol's price comes from the stream, and it is polled less often.
_Avoid_: Streaming, connected

**Stale**:
A ticker whose symbol is not live and has had no good data (a successful poll or a tick) for max(2 × refresh interval, 5 minutes). A stale ticker is drawn gray.
_Avoid_: Old, expired, outdated

**Comparison period**:
How far back a symbol's change is measured: 1D, 1W, 1M, 3M, 6M or 1Y. Each symbol has its own.
_Avoid_: Range, timeframe

**Baseline**:
The price a symbol's change is measured against: the previous close for 1D, otherwise the close one comparison period ago.
_Avoid_: Reference price, base
