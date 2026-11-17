# Architecture Decision Records

This folder records the significant architecture decisions behind StockMonitor, using the [Michael Nygard format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions): context, decision, and consequences.

| # | Title | Status |
|---|-------|--------|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-native-appkit-with-swift-package-manager.md) | Native AppKit app built with Swift Package Manager | Accepted |
| [0003](0003-yahoo-finance-as-quote-source.md) | Yahoo Finance as the quote source | Accepted |
| [0004](0004-one-status-item-per-symbol-rendered-as-image.md) | One status item per symbol, rendered as a custom image | Accepted |
| [0005](0005-websocket-streaming-with-polling-fallback.md) | WebSocket streaming with polling fallback | Accepted |
| [0006](0006-change-baseline-and-rounding.md) | Change baseline and rounding | Accepted |
| [0007](0007-persist-settings-in-userdefaults.md) | Persist settings in UserDefaults | Accepted |
| [0008](0008-continuous-integration-on-github-actions.md) | Continuous integration on GitHub Actions | Accepted |
| [0009](0009-release-on-merge-with-label-driven-semver.md) | Release on merge with label-driven semantic versions | Accepted |

To add a decision, copy the structure of an existing record, use the next number, and add it to the table. When a decision is replaced, mark the old record "Superseded by NNNN" rather than deleting it.
