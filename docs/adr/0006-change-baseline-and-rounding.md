# 6. Change baseline and rounding

Date: 2026-11-17

## Status

Accepted

## Context

The badge shows how much the price has moved. That needs a baseline and a display format. Early builds showed values such as `-0.2600`, because the formatter used 4 decimals for any number below 1 (a rule meant for low-priced assets). Subtracting floating-point prices also produces noise such as `-0.25999999`.

## Decision

- The change is measured against the **previous close**, as in the Stocks app: `change = price - previousClose`, `changePercent = change / previousClose * 100`.
- The point change is always rounded to **2 decimals** (standard rounding, half away from zero) and shown with an explicit sign, for example `+0.26` or `-1.05`.
- The percent change is shown to 2 decimals with a sign, for example `-0.30%`. The menu toggles the badge between point and percent change.
- Prices use 2 decimals, or 4 decimals for prices below 1 (for low-priced assets).
- The badge is green when the change is zero or more, and red when it is below zero.

## Consequences

- Changes read consistently regardless of size.
- Very small moves on low-priced assets (below 0.005) show as `+0.00`.
- If the stream reports a different baseline than the poll, the poll's previous close wins, so the badge does not jump between sources.
