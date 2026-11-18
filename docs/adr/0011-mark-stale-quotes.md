# 11. Mark stale quotes

Date: 2026-11-18

## Status

Accepted. Builds on [0004](0004-one-status-item-per-symbol-rendered-as-image.md) and [0005](0005-websocket-streaming-with-polling-fallback.md).

## Context

When a poll failed and the symbol already had a quote, the error was dropped and the menu bar kept showing the old price as if it were current. For a price ticker, silently showing old data is the worst way to fail (issue #9).

## Decision

- Track, per symbol, when good data last arrived (a successful poll or a stream tick), using the local clock at receipt. The exchange time of a tick is not used, so clock differences with Yahoo do not matter.
- A quote is **stale** when that time is more than `max(2 x poll interval, 5 minutes)` ago and the symbol is not live. Live symbols (0005) are never stale. A symbol with no quote yet is "loading" or "err", not stale. The rule lives in the pure function `Staleness.isStale`, which takes the current time as a parameter.
- Record why each poll failed as a short text ("timeout", "offline", "HTTP 503"), even when an older quote exists. A successful poll or tick clears it.
- Draw a stale ticker with secondary (dimmed) text and a gray badge. The menu and tooltip replace "Updated …" with "Stale: last update …" and show "Last error: …" whenever the latest poll failed.
- Re-check staleness on every timer tick and when the interval changes, so a ticker turns gray even if no new poll result arrives.

## Consequences

- With the network down, a ticker turns gray within one poll interval after the threshold, and returns to normal on the next successful poll or tick.
- A non-streaming symbol whose market is closed is not stale as long as its polls succeed. Market-closed awareness is a separate idea.
- The stale threshold changes with the poll interval, so a user who polls every 5 minutes sees gray only after 10 minutes.
