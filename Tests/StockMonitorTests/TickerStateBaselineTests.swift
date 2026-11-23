import Foundation
import Testing
@testable import StockMonitor

/// Baselines and the change badge, through the ticker state interface only
/// (issue #47, docs/adr/0006, docs/adr/0014). Uses the comparison tests' New York
/// history fixture, where the 1M baseline on Dec 5 is Nov 5's close of 102.
@Suite("Ticker state baselines")
struct TickerStateBaselineTests {
    static let now = ComparisonTests.ny(12, 5)
    static let posix = Locale(identifier: "en_US_POSIX")

    static func history() throws -> PriceHistory {
        try QuoteService.parseHistory(QuoteParsingTests.fixture("history-gaps"))
    }

    /// AAPL at 130 with a previous close of 125, added at `now`.
    static func state(price: Double = 130) -> TickerState {
        var state = TickerState(symbols: [])
        state.add(ComparisonTests.quote(price: price))
        return state
    }

    static func view(_ state: TickerState, _ symbol: String = "AAPL", period: ComparePeriod,
                     showPercent: Bool = false) -> TickerState.View? {
        state.view(symbol, now: now, pollInterval: 60, pollIntervalLabel: "1 minute", period: period,
                   showPercent: showPercent, locale: posix, formatTime: { _ in "T" })
    }

    static func fetch(_ period: ComparePeriod) -> TickerState.BaselineFetch {
        TickerState.BaselineFetch(symbol: "AAPL", period: period, range: period.historyRange!)
    }

    /// The menu lines Comparison produces today, for comparing wording.
    static func expectedLines(_ period: ComparePeriod, _ state: BaselineState, price: Double = 130) -> [String] {
        Comparison.menuLines(quote: ComparisonTests.quote(price: price), period: period, state: state, locale: posix)
    }

    // MARK: Baselines to fetch

    @Test func oneDayNeverNeedsAFetch() {
        var state = Self.state()
        #expect(state.baselinesToFetch(now: Self.now, periods: ["AAPL": .day]) == [])
        #expect(state.baselinesToFetch(now: Self.now, periods: ["AAPL": .day]) == [])
    }

    @Test(arguments: ComparePeriod.allCases.dropFirst())
    func otherPeriodIsFetchedOncePerExchangeDay(_ period: ComparePeriod) throws {
        var state = Self.state()
        #expect(state.baselinesToFetch(now: Self.now, periods: ["AAPL": period]) == [Self.fetch(period)])
        // Not again while the request is in flight.
        #expect(state.baselinesToFetch(now: Self.now, periods: ["AAPL": period]) == [])

        state.baselineFetched("AAPL", period: period, history: try Self.history(), at: Self.now)
        // Not again after it finished, for the rest of the exchange day.
        for later in [ComparisonTests.ny(12, 5, hour: 16), ComparisonTests.ny(12, 5, hour: 23)] {
            #expect(state.baselinesToFetch(now: later, periods: ["AAPL": period]) == [])
        }
        // Again on the next exchange day.
        let nextDay = ComparisonTests.ny(12, 6, hour: 0)
        #expect(state.baselinesToFetch(now: nextDay, periods: ["AAPL": period]) == [Self.fetch(period)])
    }

    @Test func failedFetchIsRetriedOnTheNextCall() {
        var state = Self.state()
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month])
        state.baselineFetchFailed("AAPL", period: .month, error: URLError(.timedOut))
        #expect(state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month]) == [Self.fetch(.month)])
    }

    @Test func onlyTrackedSymbolsWithAGivenPeriodAreReturnedSortedBySymbol() {
        var state = TickerState(symbols: ["MSFT", "AAPL", "BZ=F"])
        let fetches = state.baselinesToFetch(now: Self.now,
                                             periods: ["MSFT": .week, "AAPL": .year, "TSLA": .month])
        #expect(fetches == [TickerState.BaselineFetch(symbol: "AAPL", period: .year, range: "2y"),
                            TickerState.BaselineFetch(symbol: "MSFT", period: .week, range: "1mo")])
    }

    @Test func switchingToOneDayMakesTheLateReplyANoOp() throws {
        var state = Self.state()
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month])
        // The user switches to 1D while the 1M request is in flight.
        #expect(state.baselinesToFetch(now: Self.now, periods: ["AAPL": .day]) == [])
        state.baselineFetched("AAPL", period: .month, history: try Self.history(), at: Self.now)

        // Back on 1M, the late reply was not stored, so it loads again.
        #expect(Self.view(state, period: .month)?.comparisonLines == Self.expectedLines(.month, .loading))
        #expect(state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month]) == [Self.fetch(.month)])
    }

    @Test func switchingToOneDayMakesTheLateFailureANoOp() {
        var state = Self.state()
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month])
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .day])
        state.baselineFetchFailed("AAPL", period: .month, error: URLError(.timedOut))
        #expect(Self.view(state, period: .month)?.comparisonLines == Self.expectedLines(.month, .loading))
    }

    @Test func replyForARemovedSymbolIsIgnoredAndLeavesNoState() throws {
        var state = Self.state()
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month])
        state.remove("AAPL")
        state.baselineFetched("AAPL", period: .month, history: try Self.history(), at: Self.now)
        #expect(Self.view(state, period: .month) == nil)
        #expect(state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month]) == [])

        // Added again, it starts clean: no baseline, nothing in flight.
        state.add(ComparisonTests.quote())
        #expect(Self.view(state, period: .month)?.comparisonLines == Self.expectedLines(.month, .loading))
        #expect(state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month]) == [Self.fetch(.month)])
    }

    @Test func failureForARemovedSymbolIsIgnoredAndLeavesNoState() {
        var state = Self.state()
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month])
        state.remove("AAPL")
        state.baselineFetchFailed("AAPL", period: .month, error: URLError(.timedOut))
        state.add(ComparisonTests.quote())
        #expect(Self.view(state, period: .month)?.comparisonLines == Self.expectedLines(.month, .loading))
    }

    @Test func baselineForAnUntrackedSymbolLeavesNoState() throws {
        var state = Self.state()
        state.baselineFetched("MSFT", period: .month, history: try Self.history(), at: Self.now)
        state.baselineFetchFailed("MSFT", period: .month, error: URLError(.timedOut))
        #expect(Self.view(state, "MSFT", period: .month) == nil)
    }

    // MARK: Badge

    @Test func oneDayBadgeUsesThePreviousCloseWithoutAPill() {
        let badge = Self.view(Self.state(), period: .day)?.badge
        #expect(badge == TickerState.Badge(text: "+5.00", change: 5, percent: 4, isUp: true, periodLabel: nil))
    }

    @Test func badgeUsesThePeriodBaselineOnceLoaded() throws {
        var state = Self.state()
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month])
        state.baselineFetched("AAPL", period: .month, history: try Self.history(), at: Self.now)
        let badge = try #require(Self.view(state, period: .month)?.badge)
        #expect(badge.change == 28)  // 130 against Nov 5's close of 102
        #expect(badge.text == "+28.00")
        #expect(badge.isUp)
        #expect(badge.periodLabel == "1M")
    }

    @Test func badgeShowsTheDailyChangeWithoutAPillWhileLoadingAndAfterAFailure() {
        var state = Self.state()
        #expect(Self.view(state, period: .week)?.badge?.periodLabel == nil)
        #expect(Self.view(state, period: .week)?.badge?.change == 5)
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .week])
        state.baselineFetchFailed("AAPL", period: .week, error: URLError(.timedOut))
        #expect(Self.view(state, period: .week)?.badge?.periodLabel == nil)
        #expect(Self.view(state, period: .week)?.badge?.change == 5)
    }

    @Test func badgeTextFollowsShowPercent() throws {
        var state = Self.state()
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month])
        state.baselineFetched("AAPL", period: .month, history: try Self.history(), at: Self.now)
        #expect(Self.view(state, period: .month, showPercent: true)?.badge?.text == "+27.45%")
        #expect(Self.view(state, period: .day, showPercent: true)?.badge?.text == "+4.00%")
        #expect(Self.view(state, period: .day, showPercent: false)?.badge?.text == "+5.00")
    }

    @Test func badgeIsDownBelowTheBaselineAndUpAtZero() {
        #expect(Self.view(Self.state(price: 120), period: .day)?.badge?.isUp == false)
        #expect(Self.view(Self.state(price: 120), period: .day)?.badge?.text == "-5.00")
        #expect(Self.view(Self.state(price: 125), period: .day)?.badge?.isUp == true)
    }

    @Test func noQuoteHasNoBadgeAndNoComparisonLines() {
        let state = TickerState(symbols: ["AAPL"])
        let view = Self.view(state, period: .month)
        #expect(view?.badge == nil)
        #expect(view?.comparisonLines == [])
    }

    // MARK: Menu comparison lines

    @Test func oneDayMenuLines() {
        #expect(Self.view(Self.state(), period: .day)?.comparisonLines == ["+5.00 (+4.00%)", "Prev close 125.00"])
    }

    @Test func loadingMenuLines() {
        #expect(Self.view(Self.state(), period: .week)?.comparisonLines
                == ["1W change: loading…", "Today +5.00 (+4.00%)", "Prev close 125.00"])
    }

    @Test func loadedMenuLines() throws {
        var state = Self.state()
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .month])
        let history = try Self.history()
        state.baselineFetched("AAPL", period: .month, history: history, at: Self.now)
        let baseline = try #require(history.baseline(for: .month, now: Self.now))
        let lines = try #require(Self.view(state, period: .month)?.comparisonLines)
        #expect(lines == Self.expectedLines(.month, .ready(baseline)))
        #expect(lines.first == "1M change +28.00 (+27.45%)")
    }

    @Test func failedMenuLines() {
        var state = Self.state()
        _ = state.baselinesToFetch(now: Self.now, periods: ["AAPL": .week])
        state.baselineFetchFailed("AAPL", period: .week, error: URLError(.notConnectedToInternet))
        #expect(Self.view(state, period: .week)?.comparisonLines
                == ["1W change unavailable (offline)", "Today +5.00 (+4.00%)", "Prev close 125.00"])
    }
}
