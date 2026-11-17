# 1. Record architecture decisions

Date: 2026-11-17

## Status

Accepted

## Context

StockMonitor depends on choices that are not obvious from the code alone: why it uses an unofficial data source, why it draws its own menu bar images, why it both streams and polls. Without a record, a future change could undo one of these choices without knowing the trade-off behind it.

## Decision

We record significant architecture decisions as short Markdown files in `docs/adr/`, numbered in order, using the Nygard format (Status, Context, Decision, Consequences).

## Consequences

- New contributors can learn why the app is built the way it is.
- A decision that changes gets a new record that supersedes the old one, so the history stays visible.
- Small, easily reversed choices do not need a record.
