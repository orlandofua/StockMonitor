# 3. Yahoo Finance as the quote source

Date: 2026-11-17

## Status

Accepted

## Context

The app must show prices for any symbol the user picks, including stocks (`AAPL`), futures (`BZ=F`), indices (`^GSPC`) and crypto (`BTC-USD`). It is a personal tool, so it should not require signing up for an API key.

Options considered:

- **Paid or key-based APIs** (for example Alpha Vantage, Finnhub, Polygon): documented and stable, but need an API key, have tight free-tier rate limits, and often cover futures poorly or not at all.
- **Yahoo Finance chart endpoint** (`https://query1.finance.yahoo.com/v8/finance/chart/<symbol>`): no key, covers all of the symbol types above, and uses the same ticker format users already know from Yahoo Finance.

## Decision

Use Yahoo Finance's public chart endpoint for polling (`QuoteService` in `Quote.swift`). From the response's `meta` object, read `regularMarketPrice`, `previousClose` (falling back to `chartPreviousClose`), `shortName`/`longName`, and `currency`. Send a browser-like `User-Agent` header, because Yahoo rejects some requests without one.

## Consequences

- No account or key is needed, and the user can add any Yahoo ticker.
- The endpoint is unofficial and undocumented. Yahoo can change or rate-limit it without notice. Requests are kept low (one per symbol per interval) to reduce that risk.
- Some data, especially futures, may be delayed by the exchange.
- All network access is isolated in `QuoteService` and `QuoteStream`, so swapping the provider later only touches those two types.
