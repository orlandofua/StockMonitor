# 7. Persist settings in UserDefaults

Date: 2026-11-17

## Status

Accepted

## Context

The app has four settings: the list of symbols, whether to show percent change, the polling interval, and each symbol's comparison period. They must survive relaunches. There is no settings window, and the data is tiny.

## Decision

Store settings in `UserDefaults.standard` (domain `com.local.StockMonitor`) under the keys `symbols` (array of strings, default `["BZ=F"]`), `showPercent` (bool, default false), `refreshInterval` (seconds, default 60), and `comparePeriods` (dictionary from symbol to period label such as `"1M"`, see [0014](0014-configurable-comparison-period-per-symbol.md)). A symbol without an entry uses `1D`, which is never stored, and removing a symbol removes its entry. Settings change only through the status item menus: Add Symbol, Remove, Show Percent Change, Compare To, and Refresh Every.

## Consequences

- No database, files, or migration code.
- Settings can be inspected or reset from the terminal, for example `defaults read com.local.StockMonitor` or `defaults delete com.local.StockMonitor`.
- Because UserDefaults reads the argument domain first, launching the binary with `-symbols '("AAPL","BTC-USD")'` overrides the list for one run, which helps with testing.
- Removing the last symbol quits the app, because no menu would remain to add one back. Relaunching with an empty list restores the default `BZ=F`.
