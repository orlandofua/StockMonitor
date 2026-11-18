import Foundation

/// How far back a symbol's change is measured (issue #16, docs/adr/0014).
enum ComparePeriod: String, CaseIterable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"

    /// A new symbol, or one without a stored period, compares to the previous close.
    static let `default` = ComparePeriod.day

    var label: String { rawValue }

    /// The Yahoo chart `range` to request for the baseline, or `nil` for 1D,
    /// which uses the quote's previous close.
    ///
    /// One size larger than the period, so the response still holds the close
    /// before a weekend or holiday that falls on the target day.
    var historyRange: String? {
        switch self {
        case .day: return nil
        case .week: return "1mo"
        case .month: return "3mo"
        case .threeMonths: return "6mo"
        case .sixMonths: return "1y"
        case .year: return "2y"
        }
    }

    /// The calendar day one period before `date`, in `calendar`'s time zone.
    /// Months and years follow the calendar, so one month before Mar 31 is Feb 28 (or 29).
    func targetDay(before date: Date, calendar: Calendar) -> Date {
        let (component, value): (Calendar.Component, Int) = {
            switch self {
            case .day: return (.day, -1)
            case .week: return (.day, -7)
            case .month: return (.month, -1)
            case .threeMonths: return (.month, -3)
            case .sixMonths: return (.month, -6)
            case .year: return (.year, -1)
            }
        }()
        let shifted = calendar.date(byAdding: component, value: value, to: date) ?? date
        return calendar.startOfDay(for: shifted)
    }
}

/// Daily closes for one symbol, oldest first, as returned by the chart endpoint.
struct PriceHistory: Equatable {
    struct Bar: Equatable {
        let time: Date
        let close: Double
    }

    let bars: [Bar]
    /// The exchange's time zone. Calendar days are counted in it.
    let timeZone: TimeZone

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The close one `period` before `now`, counted in calendar days.
    ///
    /// When the target day has no close (a weekend or holiday), the most recent
    /// close before it is used. When the history starts after the target day
    /// (for example a new listing), the earliest close is used and marked.
    /// Returns `nil` only when there are no bars.
    func baseline(for period: ComparePeriod, now: Date) -> Baseline? {
        let cal = calendar
        let target = period.targetDay(before: now, calendar: cal)
        if let bar = bars.last(where: { cal.startOfDay(for: $0.time) <= target }) {
            return Baseline(period: period, date: bar.time, close: bar.close, timeZone: timeZone,
                            isEarliestAvailable: false)
        }
        return bars.first.map {
            Baseline(period: period, date: $0.time, close: $0.close, timeZone: timeZone, isEarliestAvailable: true)
        }
    }
}

/// The close a symbol's change is measured from, for periods other than 1D.
struct Baseline: Equatable {
    let period: ComparePeriod
    /// When the bar that holds the close starts.
    let date: Date
    let close: Double
    /// The exchange's time zone, for showing `date` as the exchange's calendar day.
    let timeZone: TimeZone
    /// The history is shorter than the period, so this is the earliest close Yahoo has.
    let isEarliestAvailable: Bool
}

/// Where a symbol's baseline stands, for drawing the badge and the menu.
enum BaselineState: Equatable {
    /// 1D: the change uses the quote's previous close.
    case previousClose
    /// The history request is in flight, or not sent yet.
    case loading
    case ready(Baseline)
    /// The latest history request failed with this short reason.
    case failed(String)
}

/// Caches each symbol's baseline so history is fetched once per symbol, period
/// and exchange day, not on every poll (docs/adr/0014).
struct BaselineCache {
    private struct Entry {
        let baseline: Baseline
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    /// The period whose history request is in flight, per symbol.
    private var pending: [String: ComparePeriod] = [:]
    private var errors: [String: (period: ComparePeriod, message: String)] = [:]

    /// The baseline to show for `symbol` at `period`.
    ///
    /// A baseline from an earlier day is still returned while its replacement
    /// loads, so the badge does not flip back to the daily change at midnight.
    func state(for symbol: String, period: ComparePeriod) -> BaselineState {
        guard period != .day else { return .previousClose }
        if let entry = entries[symbol], entry.baseline.period == period { return .ready(entry.baseline) }
        if pending[symbol] != period, let error = errors[symbol], error.period == period {
            return .failed(error.message)
        }
        return .loading
    }

    /// Whether `symbol` needs a history request for `period` at `now`. When it
    /// does, the request is marked as in flight, so a second call returns false
    /// until it finishes or fails. 1D never fetches, and switching to it drops
    /// any request still in flight, so its late reply is not stored.
    mutating func beginFetch(_ symbol: String, period: ComparePeriod, now: Date) -> Bool {
        guard period != .day else {
            pending[symbol] = nil
            return false
        }
        guard pending[symbol] != period else { return false }
        if let entry = entries[symbol], entry.baseline.period == period,
           entry.baseline.calendar.isDate(entry.fetchedAt, inSameDayAs: now) {
            return false
        }
        pending[symbol] = period
        return true
    }

    /// Stores the baseline from a finished request. Returns false, and stores
    /// nothing, when the symbol has since switched to another period.
    @discardableResult
    mutating func finish(_ symbol: String, period: ComparePeriod, history: PriceHistory, now: Date) -> Bool {
        guard pending[symbol] == period else { return false }
        pending[symbol] = nil
        guard let baseline = history.baseline(for: period, now: now) else {
            errors[symbol] = (period, "no history")
            return true
        }
        entries[symbol] = Entry(baseline: baseline, fetchedAt: now)
        errors[symbol] = nil
        return true
    }

    /// Records a failed request, so the next poll tries again. Returns false
    /// when the symbol has since switched to another period.
    @discardableResult
    mutating func fail(_ symbol: String, period: ComparePeriod, message: String) -> Bool {
        guard pending[symbol] == period else { return false }
        pending[symbol] = nil
        errors[symbol] = (period, message)
        return true
    }

    /// Forgets everything about a removed symbol.
    mutating func remove(_ symbol: String) {
        entries[symbol] = nil
        pending[symbol] = nil
        errors[symbol] = nil
    }
}

extension Baseline {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// What the ticker and the menu show for a quote and its comparison period.
enum Comparison {
    struct Badge: Equatable {
        let change: Double
        let percent: Double
        /// The outlined period pill, or `nil` to hide it.
        let periodLabel: String?
    }

    /// The badge values. 1D uses the previous close, exactly as before. Other
    /// periods use their baseline once it is known. Until then the badge shows
    /// the daily change without a period pill, so the pill never labels a
    /// change it does not describe.
    static func badge(quote: Quote, state: BaselineState) -> Badge {
        if case .ready(let baseline) = state {
            return Badge(change: quote.change(from: baseline.close), percent: quote.changePercent(from: baseline.close),
                         periodLabel: baseline.period.label)
        }
        return Badge(change: quote.change, percent: quote.changePercent, periodLabel: nil)
    }

    /// The change and baseline lines of the menu.
    ///
    /// - 1D: "+0.26 (+0.28%)" and "Prev close 92.44", as before.
    /// - Other periods: "1M change +4.12 (+2.31%)", "Close on Oct 17 182.40"
    ///   (with "earliest available" for a short history), then today's change
    ///   and the previous close.
    static func menuLines(quote: Quote, period: ComparePeriod, state: BaselineState,
                          locale: Locale = .current) -> [String] {
        let daily = "\(Formatting.change(quote.change, locale: locale)) (\(Formatting.percent(quote.changePercent)))"
        let previousClose = "Prev close \(Formatting.price(quote.previousClose, locale: locale))"
        let label = period.label
        switch state {
        case .previousClose:
            return [daily, previousClose]
        case .ready(let baseline):
            let change = Formatting.change(quote.change(from: baseline.close), locale: locale)
            let percent = Formatting.percent(quote.changePercent(from: baseline.close))
            var close = "Close on \(day(baseline, locale: locale)) \(Formatting.price(baseline.close, locale: locale))"
            if baseline.isEarliestAvailable { close += " (earliest available)" }
            return ["\(label) change \(change) (\(percent))", close, "Today \(daily)", previousClose]
        case .loading:
            return ["\(label) change: loading…", "Today \(daily)", previousClose]
        case .failed(let message):
            return ["\(label) change unavailable (\(message))", "Today \(daily)", previousClose]
        }
    }

    /// The baseline's day in the exchange's time zone, such as "Oct 17".
    static func day(_ baseline: Baseline, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = baseline.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: baseline.date)
    }
}

/// Each symbol's comparison period, stored in UserDefaults under
/// `comparePeriods` as a map from symbol to label, such as `["AAPL": "1M"]`.
/// 1D is the default and is not stored.
struct ComparePeriodStore {
    static let key = "comparePeriods"

    let defaults: UserDefaults

    private var stored: [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func period(for symbol: String) -> ComparePeriod {
        stored[symbol].flatMap(ComparePeriod.init(rawValue:)) ?? .default
    }

    func set(_ period: ComparePeriod, for symbol: String) {
        var map = stored
        map[symbol] = period == .default ? nil : period.rawValue
        save(map)
    }

    func remove(_ symbol: String) {
        var map = stored
        map[symbol] = nil
        save(map)
    }

    private func save(_ map: [String: String]) {
        if map.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(map, forKey: Self.key)
        }
    }
}
