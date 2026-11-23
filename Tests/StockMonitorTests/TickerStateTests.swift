import Foundation
import Testing
@testable import StockMonitor

@Suite("Ticker state")
struct TickerStateTests {
    /// A fixed "now", so every test controls the clock.
    static let now = Date(timeIntervalSince1970: 1_794_929_270)

    static func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    static func quote(_ symbol: String = "BZ=F", price: Double = 92.16, at time: Date = now) -> Quote {
        Quote(symbol: symbol, name: "Brent Crude", price: price, previousClose: 92.44,
              currency: "USD", fetchedAt: time)
    }

    @Test func trackedSymbolWithNoQuoteShowsLoading() {
        let state = TickerState(symbols: ["BZ=F"])
        #expect(Self.view(state, "BZ=F")?.priceText == "…")
    }

    static let posix = Locale(identifier: "en_US_POSIX")

    /// Formats times as seconds since `now`, so tests do not depend on the
    /// locale or time zone.
    static func formatTime(_ date: Date) -> String { "T\(Int(date.timeIntervalSince(now)))" }

    /// The view at `now`, with a fixed locale, time format and poll interval
    /// (1 minute by default), comparing to the previous close unless told otherwise.
    static func view(_ state: TickerState, _ symbol: String, at now: Date = now,
                     interval: TimeInterval = 60, period: ComparePeriod = .day,
                     showPercent: Bool = false) -> TickerState.View? {
        state.view(symbol, now: now, pollInterval: interval, pollIntervalLabel: "1 minute", period: period,
                   showPercent: showPercent, locale: posix, formatTime: formatTime)
    }

    @Test func successfulPollShowsItsPrice() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(price: 92.16), at: Self.now)
        let view = Self.view(state, "BZ=F")
        #expect(view?.priceText == "92.16")
        #expect(view?.quote?.price == 92.16)
        #expect(view?.lastUpdate == Self.now)
    }

    @Test func failedPollWithNoQuoteShowsErr() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollFailed("BZ=F", error: URLError(.timedOut))
        let view = Self.view(state, "BZ=F")
        #expect(view?.priceText == "err")
        #expect(view?.lastError == "timeout")
    }

    @Test func failedPollKeepsLastGoodQuoteAndNextGoodDataClearsError() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(price: 92.16), at: Self.ago(60))
        state.pollFailed("BZ=F", error: URLError(.notConnectedToInternet))

        var view = Self.view(state, "BZ=F")
        #expect(view?.priceText == "92.16")
        #expect(view?.lastUpdate == Self.ago(60))
        #expect(view?.lastError == "offline")

        state.pollSucceeded(Self.quote(price: 93), at: Self.now)
        view = Self.view(state, "BZ=F")
        #expect(view?.priceText == "93.00")
        #expect(view?.lastError == nil)
    }

    // MARK: Add and remove

    @Test func addedSymbolShowsItsValidationQuoteAtOnce() {
        var state = TickerState(symbols: ["BZ=F"])
        state.add(Self.quote("AAPL", price: 230.5, at: Self.ago(5)))
        let view = Self.view(state, "AAPL")
        #expect(view?.priceText == "230.50")
        #expect(view?.lastUpdate == Self.ago(5))
        #expect(view?.lastError == nil)
    }

    @Test func removedSymbolIsForgotten() {
        var state = TickerState(symbols: ["BZ=F", "AAPL"])
        state.pollSucceeded(Self.quote("AAPL"), at: Self.now)
        state.remove("AAPL")
        #expect(Self.view(state, "AAPL") == nil)
        #expect(Self.view(state, "BZ=F") != nil)
    }

    /// Issue #42: a poll still in flight when its symbol was removed used to
    /// leave a quote, an update time and an error behind.
    @Test func pollRepliesAfterRemovalLeaveNoState() {
        var state = TickerState(symbols: ["BZ=F", "AAPL"])
        state.remove("AAPL")
        state.pollSucceeded(Self.quote("AAPL", price: 230), at: Self.now)
        state.pollFailed("AAPL", error: URLError(.timedOut))
        #expect(Self.view(state, "AAPL") == nil)

        // Adding it again starts clean, from the new check's quote only.
        state.add(Self.quote("AAPL", price: 231, at: Self.now))
        let view = Self.view(state, "AAPL")
        #expect(view?.priceText == "231.00")
        #expect(view?.lastError == nil)
    }

    // MARK: Stream ticks and the live rule (issue #46, docs/adr/0005)

    static func tick(_ symbol: String = "BZ=F", price: Double = 93, at time: Date,
                     previousClose: Double? = nil) -> StreamTick {
        StreamTick(symbol: symbol, price: price, time: time, change: nil, changePercent: nil,
                   previousClose: previousClose)
    }

    @Test func tickWithNoPreviousQuoteBuildsQuoteFromTick() {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(price: 93, at: Self.ago(3), previousClose: 90), at: Self.now)
        let quote = Self.view(state, "BZ=F")?.quote
        #expect(quote?.price == 93)
        #expect(quote?.previousClose == 90)
        #expect(quote?.name == "BZ=F")
        #expect(quote?.fetchedAt == Self.ago(3))
        #expect(Self.view(state, "BZ=F")?.lastUpdate == Self.now)
    }

    @Test func tickForUntrackedSymbolLeavesNoState() {
        var state = TickerState(symbols: ["BZ=F", "AAPL"])
        state.remove("AAPL")
        state.tickReceived(Self.tick("AAPL", at: Self.now), at: Self.now)
        state.tickReceived(Self.tick("MSFT", at: Self.now), at: Self.now)
        #expect(Self.view(state, "AAPL") == nil)
        #expect(Self.view(state, "MSFT") == nil)
    }

    @Test func tickWithPreviousQuoteKeepsPreviousCloseNameAndCurrency() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(price: 92.16, at: Self.ago(60)), at: Self.ago(60))
        state.tickReceived(Self.tick(price: 93, at: Self.ago(3), previousClose: 80), at: Self.now)
        let quote = Self.view(state, "BZ=F")?.quote
        #expect(quote?.price == 93)
        #expect(quote?.previousClose == 92.44)
        #expect(quote?.name == "Brent Crude")
        #expect(quote?.currency == "USD")
        #expect(quote?.fetchedAt == Self.ago(3))
    }

    @Test func symbolWithNoTickIsNotLive() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(), at: Self.now)
        #expect(Self.view(state, "BZ=F")?.isLive == false)
    }

    /// Live while the last tick arrived less than 120 s before `now`.
    @Test(arguments: [(0.0, true), (119, true), (119.999, true), (120, false), (121, false), (600, false)])
    func symbolIsLiveForLessThan120SecondsAfterItsLastTick(sinceTick: TimeInterval, live: Bool) {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(at: Self.ago(sinceTick + 2)), at: Self.ago(sinceTick))
        #expect(Self.view(state, "BZ=F")?.isLive == live)
    }

    @Test func pollWhileLiveKeepsStreamedPriceAndTimeAndTakesMetadata() {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(price: 93, at: Self.ago(12)), at: Self.ago(10))
        let polled = Quote(symbol: "BZ=F", name: "Brent Crude Oil", price: 91, previousClose: 90,
                           currency: "USD", fetchedAt: Self.now)
        state.pollSucceeded(polled, at: Self.now)
        let view = Self.view(state, "BZ=F")
        #expect(view?.quote?.price == 93)
        #expect(view?.quote?.fetchedAt == Self.ago(12))
        #expect(view?.quote?.name == "Brent Crude Oil")
        #expect(view?.quote?.currency == "USD")
        #expect(view?.quote?.previousClose == 90)
        #expect(view?.lastUpdate == Self.now)
        #expect(view?.isLive == true)
    }

    @Test func pollWhileNotLiveReplacesTheQuote() {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(price: 93, at: Self.ago(302)), at: Self.ago(300))
        state.pollSucceeded(Self.quote(price: 91, at: Self.now), at: Self.now)
        let quote = Self.view(state, "BZ=F")?.quote
        #expect(quote?.price == 91)
        #expect(quote?.fetchedAt == Self.now)
    }

    @Test func lateTickWhileLiveIsIgnored() {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(price: 93, at: Self.ago(12)), at: Self.ago(10))
        state.tickReceived(Self.tick(price: 92, at: Self.ago(13)), at: Self.now)
        let view = Self.view(state, "BZ=F")
        #expect(view?.quote?.price == 93)
        #expect(view?.quote?.fetchedAt == Self.ago(12))
        #expect(view?.lastUpdate == Self.ago(10))
    }

    @Test func tickWithSameStreamTimeWhileLiveIsAccepted() {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(price: 93, at: Self.ago(12)), at: Self.ago(10))
        state.tickReceived(Self.tick(price: 94, at: Self.ago(12)), at: Self.now)
        #expect(Self.view(state, "BZ=F")?.quote?.price == 94)
    }

    @Test func olderTickIsAcceptedOnceTheLiveWindowHasExpired() {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(price: 93, at: Self.ago(200)), at: Self.ago(120))
        state.tickReceived(Self.tick(price: 92, at: Self.ago(300)), at: Self.now)
        let view = Self.view(state, "BZ=F")
        #expect(view?.quote?.price == 92)
        #expect(view?.isLive == true)
    }

    /// docs/adr/0011: a poll's time is the local clock, a tick's time is the
    /// exchange clock. The out-of-order check never compares the two, so a tick
    /// stamped earlier than a poll (for example, the Mac's clock runs ahead) is
    /// still accepted.
    @Test func tickStampedBeforeAPollIsAccepted() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(price: 91, at: Self.now), at: Self.now)
        state.tickReceived(Self.tick(price: 93, at: Self.ago(30)), at: Self.now)
        let view = Self.view(state, "BZ=F")
        #expect(view?.quote?.price == 93)
        #expect(view?.isLive == true)
    }

    /// The same while live: a poll during streaming does not move the stream
    /// time that later ticks are compared with.
    @Test func pollWhileLiveDoesNotMoveTheStreamTime() {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(price: 93, at: Self.ago(60)), at: Self.ago(20))
        state.pollSucceeded(Self.quote(price: 91, at: Self.ago(10)), at: Self.ago(10))
        state.tickReceived(Self.tick(price: 94, at: Self.ago(50)), at: Self.now)
        #expect(Self.view(state, "BZ=F")?.quote?.price == 94)
    }

    @Test func statusLineSaysLiveWhileStreaming() {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(at: Self.ago(12)), at: Self.ago(10))
        #expect(Self.view(state, "BZ=F")?.statusLine == "● Live (streaming)")
    }

    @Test func statusLineNamesThePollIntervalWhenNotLive() {
        var state = TickerState(symbols: ["BZ=F"])
        #expect(state.view("BZ=F", now: Self.now, pollInterval: 60, pollIntervalLabel: "30 seconds",
                           period: .day, showPercent: false)?.statusLine
                == "Polling every 30 seconds")

        state.tickReceived(Self.tick(at: Self.ago(200)), at: Self.ago(120))
        #expect(state.view("BZ=F", now: Self.now, pollInterval: 60, pollIntervalLabel: "5 minutes",
                           period: .day, showPercent: false)?.statusLine
                == "Polling every 5 minutes")
    }

    // MARK: Staleness (issue #45, docs/adr/0011)

    /// Stale once the last good data is more than max(2 × interval, 5 minutes) old.
    /// 60 s polls hit the 5-minute floor; 300 s polls double to 10 minutes.
    @Test(arguments: [(60.0, 300.0), (300, 600)])
    func turnsStaleAtTheThreshold(interval: TimeInterval, threshold: TimeInterval) {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(at: Self.ago(threshold)), at: Self.ago(threshold))
        #expect(Self.view(state, "BZ=F", interval: interval)?.isStale == false)

        state.pollSucceeded(Self.quote(at: Self.ago(threshold + 1)), at: Self.ago(threshold + 1))
        #expect(Self.view(state, "BZ=F", interval: interval)?.isStale == true)
    }

    @Test func symbolWithNoQuoteIsNeverStale() {
        var state = TickerState(symbols: ["BZ=F"])
        #expect(Self.view(state, "BZ=F", at: Self.now.addingTimeInterval(3600))?.isStale == false)
        state.pollFailed("BZ=F", error: URLError(.timedOut))
        #expect(Self.view(state, "BZ=F", at: Self.now.addingTimeInterval(3600))?.isStale == false)
    }

    @Test func liveSymbolIsNeverStaleAndTurnsStaleAtTheThresholdOnceTheLiveWindowExpires() {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(at: Self.now), at: Self.now)
        // Live, so never stale. (The 5-minute floor keeps the threshold longer
        // than the 120 s live window, so the interval here does not matter.)
        #expect(Self.view(state, "BZ=F", at: Self.now.addingTimeInterval(100), interval: 1)?.isStale == false)
        // Not live any more, but not past the 5-minute threshold yet.
        let notLive = Self.view(state, "BZ=F", at: Self.now.addingTimeInterval(200))
        #expect(notLive?.isLive == false)
        #expect(notLive?.isStale == false)
        #expect(Self.view(state, "BZ=F", at: Self.now.addingTimeInterval(300))?.isStale == false)
        #expect(Self.view(state, "BZ=F", at: Self.now.addingTimeInterval(301))?.isStale == true)
    }

    @Test func failedPollDoesNotResetTheStaleClock() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(at: Self.ago(400)), at: Self.ago(400))
        state.pollFailed("BZ=F", error: URLError(.notConnectedToInternet))
        #expect(Self.view(state, "BZ=F")?.isStale == true)
        #expect(state.nextStaleRecheck(now: Self.now, pollInterval: 60) == nil)
    }

    @Test func successfulPollResetsTheStaleClock() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(at: Self.ago(400)), at: Self.ago(400))
        state.pollSucceeded(Self.quote(at: Self.now), at: Self.now)
        #expect(Self.view(state, "BZ=F")?.isStale == false)
    }

    @Test func tickResetsTheStaleClock() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(at: Self.ago(800)), at: Self.ago(800))
        state.tickReceived(Self.tick(at: Self.ago(200)), at: Self.ago(200))
        let view = Self.view(state, "BZ=F")
        #expect(view?.isLive == false)
        #expect(view?.isStale == false)
    }

    @Test func addedSymbolIsNotStaleRightAway() {
        var state = TickerState(symbols: ["BZ=F"])
        state.add(Self.quote("AAPL", at: Self.ago(5)))
        #expect(Self.view(state, "AAPL")?.isStale == false)
    }

    // MARK: Tooltip and menu lines

    @Test func freshQuoteLines() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(at: Self.ago(10)), at: Self.ago(5))
        let view = Self.view(state, "BZ=F")
        #expect(view?.freshnessLines == ["Updated T-10"])
        #expect(view?.tooltipLines == ["Brent Crude", "Updated T-10"])
        #expect(view?.noQuoteLine == nil)
    }

    @Test func freshQuoteWithErrorLines() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(at: Self.ago(70)), at: Self.ago(70))
        state.pollFailed("BZ=F", error: URLError(.timedOut))
        let view = Self.view(state, "BZ=F")
        #expect(view?.freshnessLines == ["Updated T-70", "Last error: timeout"])
        #expect(view?.tooltipLines == ["Brent Crude", "Updated T-70", "Last error: timeout"])
    }

    @Test func staleQuoteLines() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(at: Self.ago(900)), at: Self.ago(840))
        state.pollFailed("BZ=F", error: URLError(.notConnectedToInternet))
        let view = Self.view(state, "BZ=F")
        #expect(view?.isStale == true)
        #expect(view?.freshnessLines == ["Stale: last update T-840", "Last error: offline"])
        #expect(view?.tooltipLines == ["Brent Crude", "Stale: last update T-840", "Last error: offline"])
    }

    @Test func staleQuoteWithoutErrorLines() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(at: Self.ago(900)), at: Self.ago(900))
        #expect(Self.view(state, "BZ=F")?.freshnessLines == ["Stale: last update T-900"])
    }

    @Test func loadingSymbolLines() {
        let state = TickerState(symbols: ["BZ=F"])
        let view = Self.view(state, "BZ=F")
        #expect(view?.noQuoteLine == "BZ=F: loading…")
        #expect(view?.freshnessLines == [])
        #expect(view?.tooltipLines == ["BZ=F"])
    }

    @Test func failedSymbolLines() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollFailed("BZ=F", error: QuoteError.httpStatus(503))
        let view = Self.view(state, "BZ=F")
        #expect(view?.noQuoteLine == "BZ=F: failed to load (HTTP 503)")
        #expect(view?.freshnessLines == [])
        #expect(view?.tooltipLines == ["BZ=F"])
    }

    @Test func menuShowsNameThenPriceThenComparisonAndFreshnessLines() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(price: 92.16, at: Self.ago(10)), at: Self.ago(5))
        let view = Self.view(state, "BZ=F")
        #expect(view?.menuTitle == "Brent Crude")
        #expect(view?.menuLines == ["92.16 USD"] + (view?.comparisonLines ?? []) + ["Updated T-10"])
        #expect(view?.comparisonLines.isEmpty == false)
    }

    @Test func menuShowsOnlyTheNoQuoteLineWithoutAQuote() {
        var state = TickerState(symbols: ["BZ=F"])
        #expect(Self.view(state, "BZ=F")?.menuTitle == nil)
        #expect(Self.view(state, "BZ=F")?.menuLines == ["BZ=F: loading…"])
        state.pollFailed("BZ=F", error: QuoteError.httpStatus(503))
        #expect(Self.view(state, "BZ=F")?.menuLines == ["BZ=F: failed to load (HTTP 503)"])
    }

    // MARK: Next stale recheck

    @Test func noRecheckWithoutQuotes() {
        var state = TickerState(symbols: ["BZ=F", "AAPL"])
        state.pollFailed("BZ=F", error: URLError(.timedOut))
        #expect(state.nextStaleRecheck(now: Self.now, pollInterval: 60) == nil)
    }

    @Test func recheckIsTheEarliestThresholdCrossingAmongQuotedSymbols() {
        var state = TickerState(symbols: ["BZ=F", "AAPL", "MSFT"])
        state.pollSucceeded(Self.quote("BZ=F", at: Self.ago(10)), at: Self.ago(10))
        state.pollSucceeded(Self.quote("AAPL", at: Self.ago(200)), at: Self.ago(200))
        // MSFT has no quote, so it never turns stale.
        state.pollFailed("MSFT", error: URLError(.timedOut))
        // AAPL crosses the 5-minute threshold in 100 s, plus the 1 s margin.
        #expect(state.nextStaleRecheck(now: Self.now, pollInterval: 60) == Self.now.addingTimeInterval(101))
    }

    @Test func recheckMovesWhenTheIntervalChanges() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(at: Self.ago(200)), at: Self.ago(200))
        #expect(state.nextStaleRecheck(now: Self.now, pollInterval: 60) == Self.now.addingTimeInterval(101))
        #expect(state.nextStaleRecheck(now: Self.now, pollInterval: 300) == Self.now.addingTimeInterval(401))
    }

    @Test func recheckDropsARemovedSymbol() {
        var state = TickerState(symbols: ["BZ=F", "AAPL"])
        state.pollSucceeded(Self.quote("BZ=F", at: Self.ago(10)), at: Self.ago(10))
        state.pollSucceeded(Self.quote("AAPL", at: Self.ago(200)), at: Self.ago(200))
        state.remove("AAPL")
        #expect(state.nextStaleRecheck(now: Self.now, pollInterval: 60) == Self.now.addingTimeInterval(291))
        state.remove("BZ=F")
        #expect(state.nextStaleRecheck(now: Self.now, pollInterval: 60) == nil)
    }

    @Test func recheckFollowsTheLastGoodData() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(at: Self.ago(200)), at: Self.ago(200))
        state.tickReceived(Self.tick(at: Self.now), at: Self.now)
        #expect(state.nextStaleRecheck(now: Self.now, pollInterval: 60) == Self.now.addingTimeInterval(301))
    }

    // MARK: Symbols to poll (issue #44, docs/adr/0005)

    /// A symbol that is live at `now`: polled `sincePoll` seconds ago, then ticked.
    static func liveState(polled sincePoll: TimeInterval) -> TickerState {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollStarted("BZ=F", at: ago(sincePoll))
        state.tickReceived(tick(at: ago(12)), at: ago(10))
        return state
    }

    @Test func symbolNeverPolledIsReturned() {
        let state = TickerState(symbols: ["BZ=F", "AAPL"])
        #expect(Set(state.symbolsToPoll(now: Self.now, force: false)) == ["BZ=F", "AAPL"])
    }

    @Test(arguments: [0.0, 10, 299, 300, 3600])
    func symbolThatIsNotLiveIsAlwaysReturned(sincePoll: TimeInterval) {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollStarted("BZ=F", at: Self.ago(sincePoll))
        // Its last tick arrived 120 s ago, so the live window has just expired.
        state.tickReceived(Self.tick(at: Self.ago(122)), at: Self.ago(120))
        #expect(state.symbolsToPoll(now: Self.now, force: false) == ["BZ=F"])
    }

    /// Live symbols are polled only every 300 s unless forced.
    @Test(arguments: [(0.0, false), (10, false), (299, false), (299.999, false), (300, true), (301, true)])
    func liveSymbolIsPolledEvery300Seconds(sincePoll: TimeInterval, polled: Bool) {
        let state = Self.liveState(polled: sincePoll)
        #expect(state.symbolsToPoll(now: Self.now, force: false) == (polled ? ["BZ=F"] : []))
    }

    @Test func liveSymbolNeverPolledIsReturned() {
        var state = TickerState(symbols: ["BZ=F"])
        state.tickReceived(Self.tick(at: Self.ago(12)), at: Self.ago(10))
        #expect(state.symbolsToPoll(now: Self.now, force: false) == ["BZ=F"])
    }

    @Test func forceReturnsEveryTrackedSymbolLiveOrNot() {
        var state = TickerState(symbols: ["BZ=F", "AAPL", "MSFT"])
        state.pollStarted("BZ=F", at: Self.ago(10))
        state.tickReceived(Self.tick("BZ=F", at: Self.ago(12)), at: Self.ago(10))
        state.pollStarted("AAPL", at: Self.ago(10))
        #expect(state.symbolsToPoll(now: Self.now, force: false) == ["AAPL", "MSFT"])
        #expect(state.symbolsToPoll(now: Self.now, force: true) == ["AAPL", "BZ=F", "MSFT"])
    }

    @Test func addedSymbolCountsAsJustPolledAtItsQuoteTime() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollStarted("BZ=F", at: Self.now)
        state.add(Self.quote("AAPL", at: Self.ago(5)))
        state.tickReceived(Self.tick("AAPL", at: Self.ago(2)), at: Self.ago(1))
        state.tickReceived(Self.tick("BZ=F", at: Self.ago(2)), at: Self.ago(1))
        #expect(state.symbolsToPoll(now: Self.now, force: false) == [])
        // Both stay live. 300 s after the validation quote, AAPL is due again;
        // BZ=F, polled 5 s later, is not.
        let later = Self.now.addingTimeInterval(295)
        state.tickReceived(Self.tick("AAPL", at: later), at: later)
        state.tickReceived(Self.tick("BZ=F", at: later), at: later)
        #expect(state.symbolsToPoll(now: later, force: false) == ["AAPL"])
    }

    @Test func removedSymbolIsNeverReturned() {
        var state = TickerState(symbols: ["BZ=F", "AAPL"])
        state.remove("AAPL")
        #expect(state.symbolsToPoll(now: Self.now, force: false) == ["BZ=F"])
        #expect(state.symbolsToPoll(now: Self.now, force: true) == ["BZ=F"])
    }

    @Test func pollStartedForUntrackedSymbolLeavesNoState() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollStarted("AAPL", at: Self.now)
        #expect(state.symbolsToPoll(now: Self.now, force: true) == ["BZ=F"])
        #expect(Self.view(state, "AAPL") == nil)
    }

    @Test func removedAndReAddedSymbolStartsWithANewPollTime() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollStarted("BZ=F", at: Self.ago(400))
        state.remove("BZ=F")
        state.add(Self.quote(at: Self.ago(5)))
        state.tickReceived(Self.tick(at: Self.ago(2)), at: Self.ago(1))
        #expect(state.symbolsToPoll(now: Self.now, force: false) == [])
    }

    // MARK: Full sequence (issue #48)

    /// Add, tick, poll while live, live expires, turns stale, remove, then a
    /// late poll reply that is ignored. Polls every minute, so the stale
    /// threshold is the 5-minute floor.
    @Test func fullSequenceFromAddToALatePollReplyAfterRemoval() {
        let t0 = Self.now
        func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
        func apple(price: Double, at time: Date) -> Quote {
            Quote(symbol: "AAPL", name: "Apple Inc.", price: price, previousClose: 228, currency: "USD",
                  fetchedAt: time)
        }
        var state = TickerState(symbols: ["BZ=F"])

        // Added with the quote from its check: shown at once, counts as just polled.
        state.add(apple(price: 230, at: t0))
        #expect(Self.view(state, "AAPL", at: t0)?.priceText == "230.00")
        #expect(state.symbolsToPoll(now: at(1), force: false) == ["AAPL", "BZ=F"])

        // A tick makes it live, so the regular poll skips it.
        state.tickReceived(Self.tick("AAPL", price: 231, at: at(9)), at: at(10))
        #expect(Self.view(state, "AAPL", at: at(10))?.isLive == true)
        #expect(state.symbolsToPoll(now: at(20), force: false) == ["BZ=F"])

        // A forced poll while live keeps the streamed price and takes the metadata.
        #expect(state.symbolsToPoll(now: at(30), force: true) == ["AAPL", "BZ=F"])
        state.pollStarted("AAPL", at: at(30))
        state.pollSucceeded(apple(price: 229, at: at(31)), at: at(31))
        let live = Self.view(state, "AAPL", at: at(31))
        #expect(live?.priceText == "231.00")
        #expect(live?.menuTitle == "Apple Inc.")
        #expect(live?.statusLine == "● Live (streaming)")

        // The live window ends 120 s after the tick; not stale yet.
        #expect(Self.view(state, "AAPL", at: at(129))?.isLive == true)
        let polling = Self.view(state, "AAPL", at: at(130))
        #expect(polling?.isLive == false)
        #expect(polling?.isStale == false)
        #expect(polling?.statusLine == "Polling every 1 minute")

        // Turns stale 5 minutes after the last good data (the poll at 31 s),
        // and the recheck is scheduled for that moment.
        let recheck = state.nextStaleRecheck(now: at(130), pollInterval: 60)
        #expect(recheck.map { $0 >= at(331) && $0 < at(340) } == true)
        #expect(Self.view(state, "AAPL", at: at(331))?.isStale == false)
        let stale = Self.view(state, "AAPL", at: at(332))
        #expect(stale?.isStale == true)
        #expect(stale?.priceText == "231.00")
        #expect(stale?.freshnessLines.first?.hasPrefix("Stale: last update") == true)

        // Removed while a poll is in flight.
        state.pollStarted("AAPL", at: at(335))
        state.remove("AAPL")
        #expect(Self.view(state, "AAPL", at: at(340)) == nil)

        // The late reply, success or failure, leaves no state behind.
        state.pollSucceeded(apple(price: 240, at: at(345)), at: at(345))
        state.pollFailed("AAPL", error: URLError(.timedOut))
        #expect(Self.view(state, "AAPL", at: at(345)) == nil)
        #expect(state.symbolsToPoll(now: at(345), force: true) == ["BZ=F"])
        #expect(state.nextStaleRecheck(now: at(345), pollInterval: 60) == nil)
    }
}
