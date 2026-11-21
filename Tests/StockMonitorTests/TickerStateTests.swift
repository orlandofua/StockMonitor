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
        #expect(state.view("BZ=F")?.priceText == "…")
    }

    static let posix = Locale(identifier: "en_US_POSIX")

    @Test func successfulPollShowsItsPrice() {
        var state = TickerState(symbols: ["BZ=F"])
        state.received(Self.quote(price: 92.16), at: Self.now)
        let view = state.view("BZ=F", locale: Self.posix)
        #expect(view?.priceText == "92.16")
        #expect(view?.quote?.price == 92.16)
        #expect(view?.lastUpdate == Self.now)
    }

    @Test func failedPollWithNoQuoteShowsErr() {
        var state = TickerState(symbols: ["BZ=F"])
        state.pollFailed("BZ=F", reason: "timeout")
        let view = state.view("BZ=F")
        #expect(view?.priceText == "err")
        #expect(view?.lastError == "timeout")
    }

    @Test func failedPollKeepsLastGoodQuoteAndNextGoodDataClearsError() {
        var state = TickerState(symbols: ["BZ=F"])
        state.received(Self.quote(price: 92.16), at: Self.ago(60))
        state.pollFailed("BZ=F", reason: "offline")

        var view = state.view("BZ=F", locale: Self.posix)
        #expect(view?.priceText == "92.16")
        #expect(view?.lastUpdate == Self.ago(60))
        #expect(view?.lastError == "offline")

        state.received(Self.quote(price: 93), at: Self.now)
        view = state.view("BZ=F", locale: Self.posix)
        #expect(view?.priceText == "93.00")
        #expect(view?.lastError == nil)
    }

    // MARK: Add and remove

    @Test func addedSymbolShowsItsValidationQuoteAtOnce() {
        var state = TickerState(symbols: ["BZ=F"])
        state.add(Self.quote("AAPL", price: 230.5, at: Self.ago(5)))
        let view = state.view("AAPL", locale: Self.posix)
        #expect(view?.priceText == "230.50")
        #expect(view?.lastUpdate == Self.ago(5))
        #expect(view?.lastError == nil)
    }

    @Test func removedSymbolIsForgotten() {
        var state = TickerState(symbols: ["BZ=F", "AAPL"])
        state.received(Self.quote("AAPL"), at: Self.now)
        state.remove("AAPL")
        #expect(state.view("AAPL") == nil)
        #expect(state.view("BZ=F") != nil)
    }

    /// Issue #42: a poll still in flight when its symbol was removed used to
    /// leave a quote, an update time and an error behind.
    @Test func pollRepliesAfterRemovalLeaveNoState() {
        var state = TickerState(symbols: ["BZ=F", "AAPL"])
        state.remove("AAPL")
        state.received(Self.quote("AAPL", price: 230), at: Self.now)
        state.pollFailed("AAPL", reason: "timeout")
        #expect(state.view("AAPL") == nil)

        // Adding it again starts clean, from the new check's quote only.
        state.add(Self.quote("AAPL", price: 231, at: Self.now))
        let view = state.view("AAPL", locale: Self.posix)
        #expect(view?.priceText == "231.00")
        #expect(view?.lastError == nil)
    }
}
