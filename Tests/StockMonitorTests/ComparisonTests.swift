import Foundation
import Testing
@testable import StockMonitor

/// `Fixtures/chart/history-gaps.json` is a daily chart in the chart endpoint's
/// shape for Nov 3 to Dec 5, 2025 on a New York exchange: no bars on weekends or
/// on Thanksgiving (Nov 27), and a `null` close on Nov 19. Closes count up from
/// 100 (Nov 3) by one per bar, so each close identifies its day.
@Suite("Comparison period")
struct ComparisonTests {
    static let newYork = TimeZone(identifier: "America/New_York")!
    static let utc = TimeZone(identifier: "UTC")!

    static func history() throws -> PriceHistory {
        try QuoteService.parseHistory(QuoteParsingTests.fixture("history-gaps"))
    }

    /// A moment on a calendar day in New York, 3 pm by default.
    static func ny(_ month: Int, _ day: Int, hour: Int = 15, year: Int = 2025) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func quote(price: Double = 130, previousClose: Double = 125) -> Quote {
        Quote(symbol: "AAPL", name: "Apple Inc.", price: price, previousClose: previousClose,
              currency: "USD", fetchedAt: ny(12, 5))
    }

    static func baseline(_ period: ComparePeriod = .month, close: Double = 120, earliest: Bool = false) -> Baseline {
        Baseline(period: period, date: ny(10, 17, hour: 9), close: close, timeZone: newYork,
                 isEarliestAvailable: earliest)
    }

    // MARK: Periods

    @Test func offersExactlyTheSixPeriods() {
        #expect(ComparePeriod.allCases.map(\.label) == ["1D", "1W", "1M", "3M", "6M", "1Y"])
        #expect(ComparePeriod.default == .day)
    }

    @Test func onlyOneDayNeedsNoHistory() {
        #expect(ComparePeriod.day.historyRange == nil)
        #expect(ComparePeriod.allCases.dropFirst().allSatisfy { $0.historyRange != nil })
    }

    @Test(arguments: [
        (ComparePeriod.week, 2025, 3, 24),
        (.month, 2025, 2, 28),       // Mar 31 minus one month clamps to the end of February
        (.threeMonths, 2024, 12, 31),
        (.sixMonths, 2024, 9, 30),
        (.year, 2024, 3, 31),
    ])
    func targetDayCountsCalendarDays(_ period: ComparePeriod, _ year: Int, _ month: Int, _ day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.newYork
        let target = period.targetDay(before: Self.ny(3, 31), calendar: calendar)
        #expect(target == calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    // MARK: Parsing history

    @Test func parsesDailyClosesAndDropsNulls() throws {
        let history = try Self.history()
        #expect(history.timeZone == Self.newYork)
        #expect(history.bars.count == 23)  // 24 trading days, one with a null close
        #expect(history.bars.first?.close == 100)
        #expect(history.bars.last?.close == 123)
    }

    @Test(arguments: [
        ("stock-AAPL", "America/New_York", 354.29998779296875),
        ("future-BZF", "America/New_York", 93.44999694824219),
        ("index-GSPC", "America/New_York", 7385.1201171875),
        ("crypto-BTC-USD", "UTC", 65048.46875),
    ])
    func parsesHistoryForEverySymbolType(_ name: String, _ zone: String, _ close: Double) throws {
        let history = try QuoteService.parseHistory(QuoteParsingTests.fixture(name))
        #expect(history.timeZone == TimeZone(identifier: zone))
        #expect(history.bars.map(\.close) == [close])
    }

    @Test func historyWithoutClosesIsBadResponse() throws {
        let data = try QuoteParsingTests.fixture("no-price")
        #expect(throws: QuoteError.badResponse) { try QuoteService.parseHistory(data) }
    }

    @Test func historyErrorsMatchQuoteErrors() throws {
        let data = try QuoteParsingTests.fixture("not-found")
        #expect(throws: QuoteError.notFound) { try QuoteService.parseHistory(data, statusCode: 404) }
        #expect(throws: QuoteError.httpStatus(503)) { try QuoteService.parseHistory(Data(), statusCode: 503) }
    }

    @Test func timeZoneFallsBackToGMTOffset() throws {
        let body = #"{"chart":{"result":[{"meta":{"symbol":"X","gmtoffset":3600},"timestamp":[1],"indicators":{"quote":[{"close":[2.5]}]}}],"error":null}}"#
        let history = try QuoteService.parseHistory(Data(body.utf8))
        #expect(history.timeZone.secondsFromGMT() == 3600)
    }

    @Test func historyURLUsesTheRange() {
        let url = QuoteService.chartURL("BZ=F", range: "3mo")
        #expect(url.absoluteString == "https://query1.finance.yahoo.com/v8/finance/chart/BZ%3DF?interval=1d&range=3mo")
    }

    // MARK: Baseline lookup

    @Test(arguments: [
        // A regular weekday one week back: that day's close.
        (12, 1, ComparePeriod.week, 115.0, 11, 24),
        // One week back is Thanksgiving: the close the day before.
        (12, 4, .week, 117.0, 11, 26),
        // One week back is a Sunday: Friday's close.
        (12, 7, .week, 118.0, 11, 28),
        // One week back is a Saturday: Friday's close.
        (11, 15, .week, 104.0, 11, 7),
        // One week back has a null close: the close the day before.
        (11, 26, .week, 111.0, 11, 18),
        // One month back.
        (12, 5, .month, 102.0, 11, 5),
        // One month back is the first bar.
        (12, 3, .month, 100.0, 11, 3),
    ])
    func baselineUsesTheCloseOnOrBeforeTheTargetDay(_ month: Int, _ day: Int, _ period: ComparePeriod,
                                                    _ close: Double, _ closeMonth: Int, _ closeDay: Int) throws {
        let baseline = try #require(try Self.history().baseline(for: period, now: Self.ny(month, day)))
        #expect(baseline.close == close)
        #expect(baseline.period == period)
        #expect(!baseline.isEarliestAvailable)
        #expect(Comparison.day(baseline, locale: Locale(identifier: "en_US")) == Self.dayLabel(closeMonth, closeDay))
    }

    static func dayLabel(_ month: Int, _ day: Int) -> String {
        ["Nov", "Dec"][month - 11] + " \(day)"
    }

    @Test func calendarDaysAreCountedInTheExchangeTimeZone() throws {
        // 10 pm on Monday Dec 1 in New York is already Tuesday in UTC.
        // A week back is Monday Nov 24 in New York, not Tuesday Nov 25.
        let baseline = try #require(try Self.history().baseline(for: .week, now: Self.ny(12, 1, hour: 22)))
        #expect(baseline.close == 115)
    }

    @Test(arguments: [ComparePeriod.threeMonths, .sixMonths, .year])
    func shortHistoryFallsBackToTheEarliestClose(_ period: ComparePeriod) throws {
        let baseline = try #require(try Self.history().baseline(for: period, now: Self.ny(12, 5)))
        #expect(baseline.close == 100)
        #expect(baseline.isEarliestAvailable)
    }

    @Test func cryptoTradesOnWeekends() throws {
        // Daily bars at midnight UTC, including Saturday and Sunday.
        let days = (0..<10).map { 1_764_547_200 + $0 * 86_400 }  // Dec 1 to Dec 10, 2025
        let closes = days.indices.map { "\(90_000 + $0)" }.joined(separator: ",")
        let body = #"{"chart":{"result":[{"meta":{"symbol":"BTC-USD","exchangeTimezoneName":"UTC","gmtoffset":0},"timestamp":["#
            + days.map(String.init).joined(separator: ",") + #"],"indicators":{"quote":[{"close":["# + closes + "]}]}}],\"error\":null}}"
        let history = try QuoteService.parseHistory(Data(body.utf8))
        // Sunday Dec 14 minus one week is Sunday Dec 7, which has a bar.
        let now = Date(timeIntervalSince1970: 1_764_547_200 + 13 * 86_400 + 3_600)
        let baseline = try #require(history.baseline(for: .week, now: now))
        #expect(baseline.close == 90_006)
        #expect(Comparison.day(baseline, locale: Locale(identifier: "en_US")) == "Dec 7")
    }

    @Test func emptyHistoryHasNoBaseline() {
        #expect(PriceHistory(bars: [], timeZone: Self.utc).baseline(for: .week, now: Date()) == nil)
    }

    // MARK: Badge

    @Test func oneDayBadgeIsTheDailyChangeWithoutPill() {
        let q = Self.quote()
        let badge = Comparison.badge(quote: q, state: .previousClose)
        #expect(badge == Comparison.Badge(change: q.change, percent: q.changePercent, periodLabel: nil))
        #expect(badge.change == 5)
    }

    @Test(arguments: ComparePeriod.allCases.dropFirst())
    func otherPeriodsUseTheirBaselineAndShowThePill(_ period: ComparePeriod) {
        let badge = Comparison.badge(quote: Self.quote(price: 130), state: .ready(Self.baseline(period, close: 100)))
        #expect(badge.change == 30)
        #expect(badge.percent == 30)
        #expect(badge.periodLabel == period.label)
    }

    @Test(arguments: [BaselineState.loading, .failed("timeout")])
    func badgeShowsTheDailyChangeUntilTheBaselineIsKnown(_ state: BaselineState) {
        let badge = Comparison.badge(quote: Self.quote(), state: state)
        #expect(badge.change == 5)
        #expect(badge.periodLabel == nil)
    }

    @Test func streamedPriceMovesThePeriodChangeButNotTheBaseline() {
        let tick = StreamTick(symbol: "AAPL", price: 140, time: Self.ny(12, 5, hour: 16), change: nil,
                              changePercent: nil, previousClose: 1)
        let q = Quote.applying(tick, to: Self.quote())
        let badge = Comparison.badge(quote: q, state: .ready(Self.baseline(close: 100)))
        #expect(badge.change == 40)
        #expect(q.previousClose == 125)  // the poll's previous close still wins (ADR-0006)
    }

    // MARK: Menu

    static let enUS = Locale(identifier: "en_US")

    @Test func oneDayMenuIsUnchanged() {
        let lines = Comparison.menuLines(quote: Self.quote(), period: .day, state: .previousClose, locale: Self.enUS)
        #expect(lines == ["+5.00 (+4.00%)", "Prev close 125.00"])
    }

    @Test func periodMenuShowsPeriodChangeBaselineAndToday() {
        let lines = Comparison.menuLines(quote: Self.quote(price: 186.52, previousClose: 185.52), period: .month,
                                         state: .ready(Self.baseline(close: 182.40)), locale: Self.enUS)
        #expect(lines == ["1M change +4.12 (+2.26%)", "Close on Oct 17 182.40",
                          "Today +1.00 (+0.54%)", "Prev close 185.52"])
    }

    @Test func shortHistoryIsMarkedInTheMenu() {
        let lines = Comparison.menuLines(quote: Self.quote(), period: .year,
                                         state: .ready(Self.baseline(.year, close: 100, earliest: true)), locale: Self.enUS)
        #expect(lines[0] == "1Y change +30.00 (+30.00%)")
        #expect(lines[1] == "Close on Oct 17 100.00 (earliest available)")
    }

    @Test func loadingAndFailedMenusStillShowToday() {
        let loading = Comparison.menuLines(quote: Self.quote(), period: .week, state: .loading, locale: Self.enUS)
        #expect(loading == ["1W change: loading…", "Today +5.00 (+4.00%)", "Prev close 125.00"])
        let failed = Comparison.menuLines(quote: Self.quote(), period: .week, state: .failed("offline"), locale: Self.enUS)
        #expect(failed[0] == "1W change unavailable (offline)")
    }
}

@Suite("Baseline cache")
struct BaselineCacheTests {
    static let now = ComparisonTests.ny(12, 5)

    static func history() throws -> PriceHistory { try ComparisonTests.history() }

    @Test func oneDayNeverFetches() {
        var cache = BaselineCache()
        let ok1 = cache.beginFetch("AAPL", period: .day, now: Self.now)
        #expect(!ok1)
        #expect(cache.state(for: "AAPL", period: .day) == .previousClose)
    }

    @Test func aPeriodChangeSendsOneRequestAndPollsDoNotRefetch() throws {
        var cache = BaselineCache()
        let ok2 = cache.beginFetch("AAPL", period: .month, now: Self.now)
        #expect(ok2)
        #expect(cache.state(for: "AAPL", period: .month) == .loading)
        // Polls while the request is in flight.
        let ok3 = cache.beginFetch("AAPL", period: .month, now: Self.now)
        #expect(!ok3)
        let ok4 = cache.finish("AAPL", period: .month, history: try Self.history(), now: Self.now)
        #expect(ok4)
        guard case .ready(let baseline) = cache.state(for: "AAPL", period: .month) else {
            Issue.record("expected a baseline"); return
        }
        #expect(baseline.close == 102)
        // Later polls on the same exchange day.
        for minutes in [1, 30, 60, 6 * 60] {
            let ok5 = cache.beginFetch("AAPL", period: .month, now: Self.now.addingTimeInterval(Double(minutes) * 60))
            #expect(!ok5)
        }
    }

    @Test func refetchesOnTheNextExchangeDay() throws {
        var cache = BaselineCache()
        _ = cache.beginFetch("AAPL", period: .week, now: Self.now)
        cache.finish("AAPL", period: .week, history: try Self.history(), now: Self.now)
        let nextDay = ComparisonTests.ny(12, 6, hour: 0)
        let ok6 = cache.beginFetch("AAPL", period: .week, now: nextDay)
        #expect(ok6)
        // The old baseline stays visible while the new one loads.
        #expect(cache.state(for: "AAPL", period: .week) != .loading)
    }

    @Test func switchingPeriodsDropsTheOlderResponse() throws {
        var cache = BaselineCache()
        let ok7 = cache.beginFetch("AAPL", period: .week, now: Self.now)
        #expect(ok7)
        let ok8 = cache.beginFetch("AAPL", period: .month, now: Self.now)
        #expect(ok8)
        let ok9 = cache.finish("AAPL", period: .week, history: try Self.history(), now: Self.now)
        #expect(!ok9)
        #expect(cache.state(for: "AAPL", period: .month) == .loading)
        let ok10 = cache.finish("AAPL", period: .month, history: try Self.history(), now: Self.now)
        #expect(ok10)
        #expect(cache.state(for: "AAPL", period: .week) == .loading)  // a cached 1M is not a 1W baseline
    }

    @Test func switchingToOneDayDropsTheInFlightResponse() throws {
        var cache = BaselineCache()
        let started = cache.beginFetch("AAPL", period: .week, now: Self.now)
        #expect(started)
        let dayFetch = cache.beginFetch("AAPL", period: .day, now: Self.now)
        #expect(!dayFetch)
        let stored = cache.finish("AAPL", period: .week, history: try Self.history(), now: Self.now)
        #expect(!stored)
        #expect(cache.state(for: "AAPL", period: .week) == .loading)
        let refetch = cache.beginFetch("AAPL", period: .week, now: Self.now)
        #expect(refetch)  // switching back to 1W sends a new request
    }

    @Test func symbolsAreIndependent() throws {
        var cache = BaselineCache()
        _ = cache.beginFetch("AAPL", period: .month, now: Self.now)
        cache.finish("AAPL", period: .month, history: try Self.history(), now: Self.now)
        #expect(cache.state(for: "BTC-USD", period: .day) == .previousClose)
        let ok11 = cache.beginFetch("BTC-USD", period: .year, now: Self.now)
        #expect(ok11)
        guard case .ready = cache.state(for: "AAPL", period: .month) else {
            Issue.record("AAPL lost its baseline"); return
        }
    }

    @Test func failureIsShownAndRetriedOnTheNextPoll() {
        var cache = BaselineCache()
        _ = cache.beginFetch("AAPL", period: .week, now: Self.now)
        let ok12 = cache.fail("AAPL", period: .week, message: "timeout")
        #expect(ok12)
        #expect(cache.state(for: "AAPL", period: .week) == .failed("timeout"))
        let ok13 = cache.beginFetch("AAPL", period: .week, now: Self.now)
        #expect(ok13)
        #expect(cache.state(for: "AAPL", period: .week) == .loading)
    }

    @Test func emptyHistoryIsAFailure() {
        var cache = BaselineCache()
        _ = cache.beginFetch("NEW", period: .week, now: Self.now)
        cache.finish("NEW", period: .week, history: PriceHistory(bars: [], timeZone: ComparisonTests.utc), now: Self.now)
        #expect(cache.state(for: "NEW", period: .week) == .failed("no history"))
    }

    @Test func removeForgetsTheSymbol() throws {
        var cache = BaselineCache()
        _ = cache.beginFetch("AAPL", period: .week, now: Self.now)
        cache.finish("AAPL", period: .week, history: try Self.history(), now: Self.now)
        cache.remove("AAPL")
        #expect(cache.state(for: "AAPL", period: .week) == .loading)
        let ok14 = cache.beginFetch("AAPL", period: .week, now: Self.now)
        #expect(ok14)
    }
}

@Suite("Compare period settings")
struct ComparePeriodStoreTests {
    static func store() -> (ComparePeriodStore, UserDefaults) {
        let name = "ComparePeriodStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (ComparePeriodStore(defaults: defaults), defaults)
    }

    @Test func newSymbolDefaultsToOneDay() {
        #expect(Self.store().0.period(for: "AAPL") == .day)
    }

    @Test func periodsPersistPerSymbol() {
        let (store, defaults) = Self.store()
        store.set(.week, for: "AAPL")
        store.set(.year, for: "BTC-USD")
        // A fresh store on the same defaults stands in for a relaunch.
        let relaunched = ComparePeriodStore(defaults: defaults)
        #expect(relaunched.period(for: "AAPL") == .week)
        #expect(relaunched.period(for: "BTC-USD") == .year)
        #expect(relaunched.period(for: "BZ=F") == .day)
        #expect(defaults.dictionary(forKey: "comparePeriods") as? [String: String] == ["AAPL": "1W", "BTC-USD": "1Y"])
    }

    @Test func removingASymbolDropsItsEntry() {
        let (store, defaults) = Self.store()
        store.set(.month, for: "AAPL")
        store.set(.week, for: "^GSPC")
        store.remove("AAPL")
        #expect(store.period(for: "AAPL") == .day)
        #expect(defaults.dictionary(forKey: "comparePeriods") as? [String: String] == ["^GSPC": "1W"])
        store.remove("^GSPC")
        #expect(defaults.object(forKey: "comparePeriods") == nil)
    }

    @Test func oneDayIsNotStored() {
        let (store, defaults) = Self.store()
        store.set(.month, for: "AAPL")
        store.set(.day, for: "AAPL")
        #expect(defaults.object(forKey: "comparePeriods") == nil)
    }

    @Test func unknownStoredValueFallsBackToOneDay() {
        let (store, defaults) = Self.store()
        defaults.set(["AAPL": "5Y"], forKey: "comparePeriods")
        #expect(store.period(for: "AAPL") == .day)
    }
}
