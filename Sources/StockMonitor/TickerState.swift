import Foundation

/// Everything the app knows about each tracked symbol that decides what its
/// ticker and menu show (issue #42).
struct TickerState {
    /// What one ticker shows.
    struct View {
        let priceText: String
        let quote: Quote?
        /// When good data last arrived, by the local clock (docs/adr/0011).
        let lastUpdate: Date?
        /// Why the latest poll failed (short text such as "timeout"), until good data arrives.
        let lastError: String?
    }

    private struct Entry {
        var quote: Quote?
        var lastUpdate: Date?
        var lastError: String?
    }

    private var entries: [String: Entry] = [:]

    init(symbols: [String]) {
        for symbol in symbols { entries[symbol] = Entry() }
    }

    /// Starts tracking a symbol with the quote from its Add Symbol check, so it
    /// shows a price at once. The quote's time counts as the last good data.
    mutating func add(_ quote: Quote) {
        entries[quote.symbol] = Entry(quote: quote, lastUpdate: quote.fetchedAt)
    }

    /// Stops tracking a symbol and forgets everything about it. Later events for
    /// it, such as a poll that was still in flight, are ignored.
    mutating func remove(_ symbol: String) {
        entries[symbol] = nil
    }

    /// Good data arrived for the quote's symbol at local time `now`.
    mutating func received(_ quote: Quote, at now: Date) {
        guard entries[quote.symbol] != nil else { return }
        entries[quote.symbol]?.quote = quote
        entries[quote.symbol]?.lastUpdate = now
        entries[quote.symbol]?.lastError = nil
    }

    /// A poll failed. The last good quote, if any, stays on show.
    mutating func pollFailed(_ symbol: String, reason: String) {
        guard entries[symbol] != nil else { return }
        entries[symbol]?.lastError = reason
    }

    func view(_ symbol: String, locale: Locale = .current) -> View? {
        guard let entry = entries[symbol] else { return nil }
        let priceText = entry.quote.map { Formatting.price($0.price, locale: locale) }
            ?? (entry.lastError != nil ? "err" : "…")
        return View(priceText: priceText, quote: entry.quote, lastUpdate: entry.lastUpdate,
                    lastError: entry.lastError)
    }
}
