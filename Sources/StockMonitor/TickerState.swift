import Foundation

/// The ticker state of every tracked symbol: everything the app knows about
/// one tracked symbol that decides what its ticker and menu show (issue #42,
/// GLOSSARY.md).
///
/// The app passes in events (symbol added or removed, poll started, succeeded
/// or failed, tick received, baseline fetched or failed), each with the current
/// time. It then asks what each ticker shows (price, live or stale, change
/// against the baseline for the symbol's comparison period), which symbols to
/// poll, which baselines to fetch, and when a ticker can next turn stale (no
/// good data for too long).
/// Events for a symbol that is no longer tracked are ignored. The staleness,
/// comparison and quote-merge helpers are meant to be called only from here.
struct TickerState {
    /// What one ticker shows.
    struct View {
        let priceText: String
        /// The current quote. The app draws from the lines below instead;
        /// tests read it to check which price and metadata were kept.
        let quote: Quote?
        /// When good data last arrived, by the local clock (docs/adr/0011).
        let lastUpdate: Date?
        /// Why the latest poll failed (short text such as "timeout"), until good data arrives.
        let lastError: String?
        /// Whether the symbol is streaming: a tick arrived less than `liveWindow` ago.
        let isLive: Bool
        /// Whether no good data has arrived for the stale threshold (docs/adr/0011). Never
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
        /// The menu's bold title: the symbol's name, or `nil` when there is no quote.
        let menuTitle: String?
        /// The menu's quote section below the title: the price and currency,
        /// the comparison lines and the freshness lines; or only `noQuoteLine`
        /// when there is no quote.
        let menuLines: [String]
        /// The menu's status line: "● Live (streaming)" or "Polling every <interval>".
        let statusLine: String
        /// The ticker's change badge, or `nil` when there is no quote.
        let badge: Badge?
        /// The menu's change and baseline lines for the symbol's comparison
        /// period (docs/adr/0014). Empty when there is no quote.
        let comparisonLines: [String]
    }

    /// The change badge on a ticker (docs/adr/0006, docs/adr/0014).
    struct Badge: Equatable {
        /// The point or percent change, as the "show percent" setting picks.
        let text: String
        let change: Double
        let percent: Double
        /// Green when the change is zero or more, red below zero.
        let isUp: Bool
        /// The outlined period pill, such as "1W", or `nil` to hide it.
        let periodLabel: String?
    }

    /// A history request to run for a symbol's comparison baseline.
    struct BaselineFetch: Equatable {
        let symbol: String
        /// Never 1D, which needs no history.
        let period: ComparePeriod
        /// The chart `range` to request: `period.historyRange`.
        let range: String
    }

    /// A symbol is live while its last tick arrived less than this long ago (docs/adr/0005).
    static let liveWindow: TimeInterval = 120
    /// Live symbols are still polled this often, to refresh name, currency and
    /// previous close (docs/adr/0005).
    static let livePollInterval: TimeInterval = 300

    private struct Entry {
        var quote: Quote?
        var lastUpdate: Date?
        var lastError: String?
        /// When the last accepted tick arrived, by the local clock. Decides "live".
        var lastTickReceived: Date?
        /// The exchange time of the last accepted tick. Only ever compared with
        /// other tick times, never with a local poll time (docs/adr/0011).
        var lastTickTime: Date?
        /// When the last poll started, by the local clock.
        var lastPoll: Date?

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
    /// Baselines for periods other than 1D, fetched once per symbol, period and
    /// exchange day (docs/adr/0014).
    private var baselines = BaselineCache()

    init(symbols: [String]) {
        for symbol in symbols { entries[symbol] = Entry() }
    }

    /// Starts tracking a symbol with the quote from its Add Symbol check, so it
    /// shows a price at once. The quote's time counts as the last good data
    /// and as the last poll.
    mutating func add(_ quote: Quote) {
        entries[quote.symbol] = Entry(quote: quote, lastUpdate: quote.fetchedAt, lastPoll: quote.fetchedAt)
    }

    /// Stops tracking a symbol and forgets everything about it. Later events for
    /// it, such as a poll that was still in flight, are ignored.
    mutating func remove(_ symbol: String) {
        entries[symbol] = nil
        baselines.remove(symbol)
    }

    /// A poll for the symbol started at local time `now`.
    mutating func pollStarted(_ symbol: String, at now: Date) {
        guard entries[symbol] != nil else { return }
        entries[symbol]?.lastPoll = now
    }

    /// The tracked symbols to poll at local time `now`, sorted by symbol.
    ///
    /// A live symbol is skipped until `livePollInterval` has passed since its
    /// last poll, because the stream already keeps its price fresh. `force`
    /// (Refresh Now, wake and network recovery) returns every tracked symbol
    /// (docs/adr/0005).
    func symbolsToPoll(now: Date, force: Bool) -> [String] {
        entries.filter { _, entry in
            guard !force, entry.isLive(at: now), let lastPoll = entry.lastPoll else { return true }
            return now.timeIntervalSince(lastPoll) >= TickerState.livePollInterval
        }.keys.sorted()
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

    /// A poll failed with `error`, recorded as its short summary such as
    /// "timeout". The last good quote, if any, stays on show.
    mutating func pollFailed(_ symbol: String, error: Error) {
        guard entries[symbol] != nil else { return }
        entries[symbol]?.lastError = Staleness.errorSummary(error)
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

    /// The history requests to run at `now` for the tracked symbols in
    /// `periods`, which maps a symbol to its comparison period. Sorted by symbol.
    ///
    /// The returned requests count as started: they are not returned again
    /// while in flight, nor after they finish on the same exchange day. 1D never
    /// needs a request, and passing 1D for a symbol drops its request in flight,
    /// so a late reply is ignored (docs/adr/0014).
    mutating func baselinesToFetch(now: Date, periods: [String: ComparePeriod]) -> [BaselineFetch] {
        periods.keys.sorted().compactMap { symbol in
            guard entries[symbol] != nil, let period = periods[symbol] else { return nil }
            guard let range = period.historyRange else {
                // 1D: never starts a request, but drops the one in flight.
                _ = baselines.beginFetch(symbol, period: period, now: now)
                return nil
            }
            guard baselines.beginFetch(symbol, period: period, now: now) else { return nil }
            return BaselineFetch(symbol: symbol, period: period, range: range)
        }
    }

    /// A history request finished at `now`. Ignored when the symbol is no longer
    /// tracked or has since switched to another period.
    mutating func baselineFetched(_ symbol: String, period: ComparePeriod, history: PriceHistory, at now: Date) {
        guard entries[symbol] != nil else { return }
        baselines.finish(symbol, period: period, history: history, now: now)
    }

    /// A history request failed with `error`, recorded as its short summary,
    /// so the next call to `baselinesToFetch` tries again. Ignored when the
    /// symbol is no longer tracked or has since switched to another period.
    mutating func baselineFetchFailed(_ symbol: String, period: ComparePeriod, error: Error) {
        guard entries[symbol] != nil else { return }
        baselines.fail(symbol, period: period, message: Staleness.errorSummary(error))
    }

    /// What the symbol's ticker and menu show at local time `now`.
    ///
    /// - Parameters:
    ///   - pollInterval: the user's refresh interval, which sets the stale threshold.
    ///   - pollIntervalLabel: names that interval, such as "1 minute".
    ///   - period: the symbol's comparison period, which picks the badge's baseline.
    ///   - showPercent: whether the badge shows the percent change instead of the point change.
    ///   - formatTime: formats the times in the freshness lines. Injected so
    ///     tests do not depend on the locale or time zone.
    func view(_ symbol: String, now: Date, pollInterval: TimeInterval, pollIntervalLabel: String,
              period: ComparePeriod, showPercent: Bool, locale: Locale = .current,
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
        let baselineState = baselines.state(for: symbol, period: period)
        let badge = entry.quote.map { quote in
            let values = Comparison.badge(quote: quote, state: baselineState)
            return Badge(text: showPercent ? Formatting.percent(values.percent)
                                           : Formatting.change(values.change, locale: locale),
                         change: values.change, percent: values.percent, isUp: values.change >= 0,
                         periodLabel: values.periodLabel)
        }
        let comparisonLines = entry.quote.map {
            Comparison.menuLines(quote: $0, period: period, state: baselineState, locale: locale)
        } ?? []
        let menuLines = entry.quote.map { quote in
            ["\(Formatting.price(quote.price, locale: locale)) \(quote.currency ?? "")"]
                + comparisonLines + freshnessLines
        } ?? noQuoteLine.map { [$0] } ?? []
        return View(priceText: priceText, quote: entry.quote, lastUpdate: entry.lastUpdate,
                    lastError: entry.lastError, isLive: isLive, isStale: isStale,
                    tooltipLines: tooltipLines, freshnessLines: freshnessLines, noQuoteLine: noQuoteLine,
                    menuTitle: entry.quote?.name, menuLines: menuLines,
                    statusLine: isLive ? "● Live (streaming)" : "Polling every \(pollIntervalLabel)",
                    badge: badge, comparisonLines: comparisonLines)
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
