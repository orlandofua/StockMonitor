# 14. Configurable comparison period per symbol

Date: 2026-11-18

## Status

Accepted. Extends [0006](0006-change-baseline-and-rounding.md).

## Context

The badge always measured the change against the previous close (0006), so the app could not show how a symbol has moved over a week, a month, or a year (issue #16). The quote poll (`range=1d`) and the stream only carry the previous close, so a longer baseline needs daily history from the chart endpoint (0003). That history changes at most once per trading day, and the endpoint is unofficial and rate-limited, so it must not be fetched on every poll.

## Decision

- Each symbol has its own comparison period: 1D, 1W, 1M, 3M, 6M, or 1Y (`ComparePeriod`). A new symbol uses 1D. There is no global setting.
- **1D is unchanged**: the change is measured against the previous close, exactly as in 0006.
- **Other periods** measure against the close one period ago, counted in calendar days in the exchange's time zone (`exchangeTimezoneName`, else `gmtoffset`). 1W is 7 days back. Months and years follow the calendar, so one month before Mar 31 is Feb 28 or 29. When the target day has no close (a weekend, a holiday, or a `null` close), the most recent close before it is used. When the history starts after the target day, such as for a new listing, the earliest close is used and the menu says "earliest available".
- The baseline comes from `v8/finance/chart/<symbol>?interval=1d&range=<r>`, where `r` is one size larger than the period (1W uses `1mo`, 1M `3mo`, 3M `6mo`, 6M `1y`, 1Y `2y`). The extra room keeps the close before a weekend or holiday at the start of the period in the response, so a full history is never mistaken for a short one.
- `BaselineCache` keeps one baseline per symbol. A symbol gets one history request when its period changes, and again only after the exchange's calendar day changes, checked on the regular poll. Only one request per symbol and period is in flight, and a response for a period the user has since left is dropped. A failed request is retried on the next poll. The previous day's baseline stays on screen while the new one loads.
- Stream ticks and polls update the price only. The baseline for periods other than 1D comes from history alone. The previous close keeps its 0006 rules and is still used for today's change.
- The badge (point or percent, green or red) uses the selected baseline. For periods other than 1D an outlined pill with the period label (such as `1W`) follows the badge. 1D shows no pill. Until the baseline has loaded, or when it fails to load, the badge shows the daily change without the pill, so the pill never labels a number it does not describe.
- The menu shows "1M change +4.12 (+2.31%)", "Close on Oct 17 182.40", then today's change and the previous close. For 1D it is unchanged.
- Periods are stored in UserDefaults under `comparePeriods` (see 0007). The pure parts (period arithmetic, baseline lookup, the cache, badge and menu text, the store) live in `Comparison.swift` and are unit-tested.

## Consequences

- Each symbol with a period other than 1D costs one extra request per day, plus one per period change.
- The baseline is the plain close, not the adjusted close, so a split or dividend inside the period shows up as a price move.
- A trading day is approximated by the exchange's calendar day. On a weekend or holiday the history is fetched again once, but the baseline does not move.
- For a futures contract, Yahoo's history follows the continuous contract, so a roll inside the period shows up as a price move.
- 0006's rounding and color rules apply unchanged to every period.
