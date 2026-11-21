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

    /// The view at `now`, with a fixed locale and a 1-minute poll interval.
    static func view(_ state: TickerState, _ symbol: String, at now: Date = now) -> TickerState.View? {
        state.view(symbol, now: now, pollIntervalLabel: "1 minute", locale: posix)
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
        state.pollFailed("BZ=F", reason: "timeout")
        let view = Self.view(state, "BZ=F")
        #expect(view?.priceText == "err")
        #expect(view?.lastError == "timeout")
    }

    @Test func failedPollKeepsLastGoodQuoteAndNextGoodDataClearsError() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollSucceeded(Self.quote(price: 92.16), at: Self.ago(60))
        state.pollFailed("BZ=F", reason: "offline")

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
        state.pollFailed("AAPL", reason: "timeout")
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
        #expect(state.view("BZ=F", now: Self.now, pollIntervalLabel: "30 seconds")?.statusLine
                == "Polling every 30 seconds")

        state.tickReceived(Self.tick(at: Self.ago(200)), at: Self.ago(120))
        #expect(state.view("BZ=F", now: Self.now, pollIntervalLabel: "5 minutes")?.statusLine
                == "Polling every 5 minutes")
    }
}
