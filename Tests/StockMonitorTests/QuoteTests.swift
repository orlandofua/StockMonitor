import Foundation
import Testing
@testable import StockMonitor

@Suite("Quote")
struct QuoteTests {
    static let t0 = Date(timeIntervalSince1970: 1_794_904_800)

    static func quote(price: Double = 92.16, previousClose: Double = 92.44, at time: Date = t0) -> Quote {
        Quote(symbol: "BZ=F", name: "Brent Crude", price: price, previousClose: previousClose,
              currency: "USD", fetchedAt: time)
    }

    static func tick(price: Double, change: Double? = nil, previousClose: Double? = nil,
                     at time: Date = t0.addingTimeInterval(10)) -> StreamTick {
        StreamTick(symbol: "BZ=F", price: price, time: time, change: change,
                   changePercent: nil, previousClose: previousClose)
    }

    @Test func changeIsMeasuredAgainstPreviousClose() {
        let q = Self.quote(price: 110, previousClose: 100)
        #expect(q.change == 10)
        #expect(q.changePercent == 10)
    }

    @Test func zeroPreviousCloseGivesZeroPercent() {
        #expect(Self.quote(price: 5, previousClose: 0).changePercent == 0)
    }

    @Test func tickKeepsPolledMetadataAndPreviousClose() {
        let previous = Self.quote()
        let tick = Self.tick(price: 93, change: 5, previousClose: 80)
        let q = Quote.applying(tick, to: previous)
        #expect(q.price == 93)
        #expect(q.previousClose == 92.44)  // poll wins over the tick's baseline
        #expect(q.name == "Brent Crude")
        #expect(q.currency == "USD")
        #expect(q.fetchedAt == tick.time)
    }

    @Test func tickWithoutPreviousQuoteUsesItsOwnPreviousClose() {
        let q = Quote.applying(Self.tick(price: 93, change: 1, previousClose: 90), to: nil)
        #expect(q.previousClose == 90)
        #expect(q.name == "BZ=F")
        #expect(q.currency == nil)
    }

    @Test func tickWithoutPreviousCloseDerivesItFromChange() {
        let q = Quote.applying(Self.tick(price: 93, change: 1.5), to: nil)
        #expect(q.previousClose == 91.5)
        #expect(q.change == 1.5)
    }

    @Test func tickWithNoBaselineShowsZeroChange() {
        let q = Quote.applying(Self.tick(price: 93), to: nil)
        #expect(q.change == 0)
    }

    @Test func pollMetadataKeepsStreamedPriceAndTime() {
        let streamed = Quote.applying(Self.tick(price: 93.1), to: Self.quote())
        let polled = Quote(symbol: "BZ=F", name: "Brent Crude Oil", price: 92.0, previousClose: 92.5,
                           currency: "USD", fetchedAt: Self.t0.addingTimeInterval(60))
        let merged = streamed.withMetadata(from: polled)
        #expect(merged.price == 93.1)
        #expect(merged.fetchedAt == streamed.fetchedAt)
        #expect(merged.previousClose == 92.5)
        #expect(merged.name == "Brent Crude Oil")
    }
}
