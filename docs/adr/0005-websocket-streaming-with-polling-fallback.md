# 5. WebSocket streaming with polling fallback

Date: 2026-11-17

## Status

Accepted. Extends [0003](0003-yahoo-finance-as-quote-source.md).

## Context

The first version polled every symbol on a fixed interval (default 1 minute), so prices could be up to a minute stale. Yahoo Finance also runs a streaming WebSocket (`wss://streamer.finance.yahoo.com/?version=2`). A client sends `{"subscribe": [...]}` and receives messages such as `{"type":"pricing","message":"<base64>"}`, where the payload is a protobuf `PricingData` message.

Testing on 2026-11-17 showed:

- `BTC-USD` and `ETH-USD` streamed a tick about every 5 seconds.
- `BZ=F` (Brent futures) sent no ticks while its market was open. Not every symbol streams.
- The stream carries price, time, change, and percent change, but often not the previous close or display name.

## Decision

Use both sources:

- **Streaming** (`QuoteStream.swift`): one WebSocket for all symbols. It subscribes and unsubscribes as the symbol list changes. It decodes `PricingData` with a small hand-written protobuf reader (fields 1 `id`, 2 `price`, 3 `time`, 8 `changePercent`, 12 `change`, 16 `previousClose`) instead of adding a protobuf dependency. It reconnects with exponential backoff (1 s up to 60 s), reconnects at once after the Mac wakes, and sends a ping every 30 seconds to detect dead connections.
- **Polling** (`QuoteService`): unchanged, and still the source of name, currency, and previous close.
- A symbol is **live** if a tick arrived in the last 2 minutes. Live symbols are polled only every 5 minutes, to refresh metadata. Other symbols are polled at the user's interval. "Refresh Now" always polls every symbol.
- When a poll result arrives for a live symbol, the app keeps the streamed price and takes only the metadata from the poll, so a slower poll never overwrites a newer tick. Out-of-order ticks are dropped.
- Each symbol's menu shows "● Live (streaming)" or "Polling every …".

## Consequences

- Symbols that stream update within seconds, with fewer HTTP requests.
- Symbols that do not stream behave exactly as before.
- The streaming protocol is unofficial and undocumented. If Yahoo changes it, decoding fails quietly and the app falls back to polling.
- Streamed prices are 32-bit floats. They are converted to `Double` through the float's shortest decimal form, so `92.16` stays `92.16` instead of becoming `92.160004`. A 32-bit float holds about 7 significant digits, so prices above about 100,000 may lose their last cent.
- The protobuf field numbers come from community reverse engineering, not from Yahoo. Only the fields listed above are relied on.
