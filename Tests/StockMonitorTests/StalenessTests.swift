import AppKit
import Foundation
import Testing
@testable import StockMonitor

@Suite("Stale quotes")
struct StalenessTests {
    /// A fixed "now", so every test controls the clock.
    static let now = Date(timeIntervalSince1970: 1_794_929_270)

    static func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    // MARK: Threshold

    @Test(arguments: [
        (15.0, 300.0),   // 2 x 15 s is below the 5 minute floor
        (60.0, 300.0),   // 2 x 1 min is below the floor
        (150.0, 300.0),  // 2 x 2.5 min equals the floor
        (300.0, 600.0),  // 2 x 5 min is above the floor
    ])
    func thresholdIsTwicePollIntervalButAtLeastFiveMinutes(interval: TimeInterval, expected: TimeInterval) {
        #expect(Staleness.threshold(pollInterval: interval) == expected)
    }

    // MARK: isStale

    @Test func freshQuoteIsNotStale() {
        #expect(!Staleness.isStale(lastUpdate: Self.ago(30), isLive: false, pollInterval: 60, now: Self.now))
    }

    @Test func quoteOlderThanThresholdIsStale() {
        #expect(Staleness.isStale(lastUpdate: Self.ago(301), isLive: false, pollInterval: 60, now: Self.now))
    }

    @Test func quoteExactlyAtThresholdIsNotYetStale() {
        #expect(!Staleness.isStale(lastUpdate: Self.ago(300), isLive: false, pollInterval: 60, now: Self.now))
    }

    @Test func longPollIntervalRaisesTheThreshold() {
        // With 5 minute polling, 7 minutes is only one missed poll.
        #expect(!Staleness.isStale(lastUpdate: Self.ago(420), isLive: false, pollInterval: 300, now: Self.now))
        #expect(Staleness.isStale(lastUpdate: Self.ago(601), isLive: false, pollInterval: 300, now: Self.now))
    }

    @Test func liveSymbolIsNeverStale() {
        #expect(!Staleness.isStale(lastUpdate: Self.ago(3600), isLive: true, pollInterval: 60, now: Self.now))
    }

    @Test func noQuoteYetIsNotStale() {
        #expect(!Staleness.isStale(lastUpdate: nil, isLive: false, pollInterval: 60, now: Self.now))
    }

    @Test func successfulUpdateClearsStaleness() {
        let old = Self.ago(900)
        #expect(Staleness.isStale(lastUpdate: old, isLive: false, pollInterval: 60, now: Self.now))
        // The next good update moves lastUpdate to now.
        #expect(!Staleness.isStale(lastUpdate: Self.now, isLive: false, pollInterval: 60, now: Self.now))
    }

    // MARK: nextRecheck

    @Test func recheckLandsJustPastTheThreshold() {
        // Updated 60 s ago with 1 minute polling: stale 240 s from now.
        let next = Staleness.nextRecheck(lastUpdates: [Self.ago(60)], pollInterval: 60, now: Self.now)
        #expect(next == Self.now.addingTimeInterval(240 + Staleness.recheckMargin))
        // At that moment the quote really is stale, and a moment before it is not.
        #expect(Staleness.isStale(lastUpdate: Self.ago(60), isLive: false, pollInterval: 60, now: next!))
        #expect(!Staleness.isStale(lastUpdate: Self.ago(60), isLive: false, pollInterval: 60,
                                   now: Self.now.addingTimeInterval(240)))
    }

    @Test func recheckFollowsTheLongerThresholdForSlowPolling() {
        // 5 minute polling: 10 minute threshold, not 5 + one interval.
        let next = Staleness.nextRecheck(lastUpdates: [Self.now], pollInterval: 300, now: Self.now)
        #expect(next == Self.now.addingTimeInterval(600 + Staleness.recheckMargin))
    }

    @Test func recheckPicksTheEarliestSymbol() {
        let next = Staleness.nextRecheck(lastUpdates: [Self.ago(10), Self.ago(200), Self.ago(100)],
                                         pollInterval: 60, now: Self.now)
        #expect(next == Self.now.addingTimeInterval(100 + Staleness.recheckMargin))
    }

    @Test func recheckSkipsQuotesThatAreAlreadyStale() {
        let next = Staleness.nextRecheck(lastUpdates: [Self.ago(900), Self.ago(30)], pollInterval: 60, now: Self.now)
        #expect(next == Self.now.addingTimeInterval(270 + Staleness.recheckMargin))
        #expect(Staleness.nextRecheck(lastUpdates: [Self.ago(900)], pollInterval: 60, now: Self.now) == nil)
    }

    @Test func noRecheckWithoutQuotes() {
        #expect(Staleness.nextRecheck(lastUpdates: [], pollInterval: 60, now: Self.now) == nil)
    }

    // MARK: Error summary

    @Test func errorSummaries() {
        #expect(Staleness.errorSummary(URLError(.timedOut)) == "timeout")
        #expect(Staleness.errorSummary(URLError(.notConnectedToInternet)) == "offline")
        #expect(Staleness.errorSummary(URLError(.networkConnectionLost)) == "offline")
        #expect(Staleness.errorSummary(URLError(.cannotFindHost)) == "host not found")
        #expect(Staleness.errorSummary(URLError(.badServerResponse)) == "network error \(URLError.Code.badServerResponse.rawValue)")
        #expect(Staleness.errorSummary(QuoteError.httpStatus(503)) == "HTTP 503")
        #expect(Staleness.errorSummary(QuoteError.notFound) == "symbol not found")
        #expect(Staleness.errorSummary(QuoteError.badResponse) == "no price in response")
    }

    // MARK: Menu lines

    static func time(_ date: Date) -> String {
        "t+\(Int(date.timeIntervalSince(now)))"
    }

    @Test func freshQuoteShowsUpdatedTime() {
        let lines = Staleness.menuLines(updatedAt: Self.ago(10), lastUpdate: Self.ago(5), lastError: nil,
                                        isStale: false, formatTime: Self.time)
        #expect(lines == ["Updated t+-10"])
    }

    @Test func freshQuoteWithFailedPollShowsLastError() {
        let lines = Staleness.menuLines(updatedAt: Self.ago(70), lastUpdate: Self.ago(70), lastError: "timeout",
                                        isStale: false, formatTime: Self.time)
        #expect(lines == ["Updated t+-70", "Last error: timeout"])
    }

    @Test func staleQuoteShowsLastGoodUpdateAndLastError() {
        let lines = Staleness.menuLines(updatedAt: Self.ago(900), lastUpdate: Self.ago(840), lastError: "offline",
                                        isStale: true, formatTime: Self.time)
        #expect(lines == ["Stale: last update t+-840", "Last error: offline"])
    }

    // MARK: Ticker colors

    @Test func staleTickerUsesGrayBadgeAndDimmedText() {
        #expect(TickerImage.badgeColor(isUp: true, isStale: true) == TickerImage.stale)
        #expect(TickerImage.badgeColor(isUp: false, isStale: true) == TickerImage.stale)
        #expect(TickerImage.textColor(isStale: true) == .secondaryLabelColor)
    }

    @Test func freshTickerKeepsGreenAndRedBadge() {
        #expect(TickerImage.badgeColor(isUp: true, isStale: false) == TickerImage.up)
        #expect(TickerImage.badgeColor(isUp: false, isStale: false) == TickerImage.down)
        #expect(TickerImage.textColor(isStale: false) == .labelColor)
    }
}
