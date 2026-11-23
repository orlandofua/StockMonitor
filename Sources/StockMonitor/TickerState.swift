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
        /// Whether the symbol is streaming: a tick arrived less than `liveWindow` ago.
        let isLive: Bool
        /// Whether the shown quote is too old to trust (docs/adr/0011). Never
        /// true while live or when there is no quote.
        let isStale: Bool
        /// The ticker's tooltip: the name and the freshness lines, or only the
        /// symbol when there is no quote yet.
        let tooltipLines: [String]
        /// The menu's freshness lines: "Updated …" or "Stale: last update …",
        /// plus "Last error: …". Empty when there is no quote.
        let freshnessLines: [String]
        /// The menu line shown instead of the quote when there is none:
        /// "<symbol>: loading…" or "<symbol>: failed to load (<reason>)".
        let noQuoteLine: String?
        /// The menu's status line: "● Live (streaming)" or "Polling every <interval>".
        let statusLine: String
    }

    /// A symbol is live while its last tick arrived less than this long ago (docs/adr/0005).
    static let liveWindow: TimeInterval = 120

    private struct Entry {
        var quote: Quote?
        var lastUpdate: Date?
        var lastError: String?
        /// When the last accepted tick arrived, by the local clock. Decides "live".
        var lastTickReceived: Date?
        /// The exchange time of the last accepted tick. Only ever compared with
        /// other tick times, never with a local poll time (docs/adr/0011).
        var lastTickTime: Date?

        /// Good data (a successful poll or an accepted tick) arrived at local time `now`.
        mutating func store(_ quote: Quote, at now: Date) {
            self.quote = quote
            lastUpdate = now
            lastError = nil
        }

        func isLive(at now: Date) -> Bool {
            guard let lastTickReceived else { return false }
            return now.timeIntervalSince(lastTickReceived) < TickerState.liveWindow
        }
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

    /// A poll for the quote's symbol succeeded at local time `now`.
    ///
    /// While the symbol is live, its streamed price is fresher than the poll's:
    /// keep the streamed price and time and take only name, currency and
    /// previous close from the poll (docs/adr/0005).
    mutating func pollSucceeded(_ quote: Quote, at now: Date) {
        guard let entry = entries[quote.symbol] else { return }
        let merged = entry.isLive(at: now) ? entry.quote.map { $0.withMetadata(from: quote) } : nil
        entries[quote.symbol]?.store(merged ?? quote, at: now)
    }

    /// A poll failed. The last good quote, if any, stays on show.
    mutating func pollFailed(_ symbol: String, reason: String) {
        guard entries[symbol] != nil else { return }
        entries[symbol]?.lastError = reason
    }

    /// A stream tick arrived at local time `now`. It builds on the previous quote.
    /// While the symbol is live, a tick older than the last accepted tick is
    /// out of order and ignored (docs/adr/0005).
    mutating func tickReceived(_ tick: StreamTick, at now: Date) {
        guard let entry = entries[tick.symbol] else { return }
        if entry.isLive(at: now), let last = entry.lastTickTime, tick.time < last { return }
        entries[tick.symbol]?.store(Quote.applying(tick, to: entry.quote), at: now)
        entries[tick.symbol]?.lastTickReceived = now
        entries[tick.symbol]?.lastTickTime = tick.time
    }

    /// What the symbol's ticker and menu show at local time `now`.
    ///
    /// - Parameters:
    ///   - pollInterval: the user's refresh interval, which sets the stale threshold.
    ///   - pollIntervalLabel: names that interval, such as "1 minute".
    ///   - formatTime: formats the times in the freshness lines. Injected so
    ///     tests do not depend on the locale or time zone.
    func view(_ symbol: String, now: Date, pollInterval: TimeInterval, pollIntervalLabel: String,
              locale: Locale = .current,
              formatTime: (Date) -> String = { $0.formatted(date: .omitted, time: .standard) }) -> View? {
        guard let entry = entries[symbol] else { return nil }
        let priceText = entry.quote.map { Formatting.price($0.price, locale: locale) }
            ?? (entry.lastError != nil ? "err" : "…")
        let isLive = entry.isLive(at: now)
        let isStale = entry.quote != nil
            && Staleness.isStale(lastUpdate: entry.lastUpdate, isLive: isLive, pollInterval: pollInterval, now: now)
        let freshnessLines = entry.quote.map {
            Staleness.menuLines(updatedAt: $0.fetchedAt, lastUpdate: entry.lastUpdate, lastError: entry.lastError,
                                isStale: isStale, formatTime: formatTime)
        } ?? []
        let tooltipLines = entry.quote.map { [$0.name] + freshnessLines } ?? [symbol]
        let noQuoteLine = entry.quote == nil
            ? entry.lastError.map { "\(symbol): failed to load (\($0))" } ?? "\(symbol): loading…"
            : nil
        return View(priceText: priceText, quote: entry.quote, lastUpdate: entry.lastUpdate,
                    lastError: entry.lastError, isLive: isLive, isStale: isStale,
                    tooltipLines: tooltipLines, freshnessLines: freshnessLines, noQuoteLine: noQuoteLine,
                    statusLine: isLive ? "● Live (streaming)" : "Polling every \(pollIntervalLabel)")
    }

    /// When the menu bar should next redraw so a ticker turns gray right at its
    /// stale threshold, instead of at the next poll (docs/adr/0011).
    ///
    /// Returns the earliest moment after `now` at which a quoted symbol crosses
    /// the threshold, plus a small margin, or `nil` when no symbol will. Live
    /// symbols count too: a redraw while they are still live changes nothing,
    /// and the caller then asks again with their newer update times.
    func nextStaleRecheck(now: Date, pollInterval: TimeInterval) -> Date? {
        let updates = entries.values.compactMap { $0.quote != nil ? $0.lastUpdate : nil }
        return Staleness.nextRecheck(lastUpdates: updates, pollInterval: pollInterval, now: now)
    }
}
