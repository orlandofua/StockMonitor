import Foundation
import Testing
@testable import StockMonitor

/// Fixtures in `Fixtures/chart/` are responses from
/// https://query1.finance.yahoo.com/v8/finance/chart/<symbol>?interval=1d&range=1d.
/// The stock, futures, index, crypto and not-found ones were captured on 2026-11-17.
/// `no-price`, `previous-close` and `no-previous-close` are the AAPL capture with fields
/// removed or added to cover the fallback rules in ADR-0003.
@Suite("Quote parsing")
struct QuoteParsingTests {
    static let t0 = Date(timeIntervalSince1970: 1_794_929_270)

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json",
                                                 subdirectory: "Fixtures/chart"),
                               "missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    static func parse(_ name: String, statusCode: Int = 200) throws -> Quote {
        try QuoteService.parse(fixture(name), statusCode: statusCode, fetchedAt: t0)
    }

    // MARK: Symbol types

    @Test func parsesStock() throws {
        let q = try Self.parse("stock-AAPL")
        #expect(q.symbol == "AAPL")
        #expect(q.name == "Apple Inc.")
        #expect(q.price == 354.3)
        #expect(q.previousClose == 352.78)  // only chartPreviousClose is present
        #expect(q.currency == "USD")
        #expect(q.fetchedAt == Self.t0)
    }

    @Test func parsesFuturesContract() throws {
        let q = try Self.parse("future-BZF")
        #expect(q.symbol == "BZ=F")
        #expect(q.name == "Brent Crude Oil Last Day Financ")  // shortName wins over longName
        #expect(q.price == 93.45)
        #expect(q.previousClose == 92.44)
        #expect(abs(q.change - 1.01) < 0.0001)
    }

    @Test func parsesIndex() throws {
        let q = try Self.parse("index-GSPC")
        #expect(q.symbol == "^GSPC")
        #expect(q.name == "S&P 500")
        #expect(q.price == 7385.12)
        #expect(q.previousClose == 7416.59)
        #expect(q.change < 0)
    }

    @Test func parsesCrypto() throws {
        let q = try Self.parse("crypto-BTC-USD")
        #expect(q.symbol == "BTC-USD")
        #expect(q.name == "Bitcoin USD")
        #expect(q.price == 65048.47)
        #expect(q.previousClose == 64828.375)
        #expect(q.currency == "USD")
    }

    // MARK: Fallback rules

    @Test func previousCloseWinsOverChartPreviousClose() throws {
        let q = try Self.parse("previous-close")
        #expect(q.previousClose == 353.10)
    }

    @Test func missingPreviousCloseFallsBackToPriceAndNameToLongName() throws {
        let q = try Self.parse("no-previous-close")
        #expect(q.previousClose == 354.3)
        #expect(q.change == 0)
        #expect(q.name == "Apple Inc.")  // from longName, shortName removed
    }

    @Test func missingPriceIsBadResponse() throws {
        let data = try Self.fixture("no-price")
        #expect(throws: QuoteError.badResponse) { try QuoteService.parse(data) }
    }

    @Test func validResultWithOddErrorShape() throws {
        let body = #"{"chart":{"result":[{"meta":{"symbol":"AAPL","regularMarketPrice":1.5,"chartPreviousClose":1.0}}],"error":"weird"}}"#
        let q = try QuoteService.parse(Data(body.utf8))
        #expect(q.price == 1.5)
    }

    @Test func validResultWithErrorObjectWithoutCode() throws {
        let body = #"{"chart":{"result":[{"meta":{"symbol":"AAPL","regularMarketPrice":1.5}}],"error":{"description":"x"}}}"#
        #expect(try QuoteService.parse(Data(body.utf8)).price == 1.5)
    }

    // MARK: Errors

    @Test func unknownSymbolIsNotFound() throws {
        let data = try Self.fixture("not-found")
        #expect(throws: QuoteError.notFound) { try QuoteService.parse(data, statusCode: 404) }
    }

    @Test func notFoundChartErrorWinsEvenWithStatus200() throws {
        let data = try Self.fixture("not-found")
        #expect(throws: QuoteError.notFound) { try QuoteService.parse(data) }
    }

    @Test(arguments: [
        (429, ""),
        (500, "<html><body>Internal Server Error</body></html>"),
        (404, #"{"finance":{"result":null,"error":{"code":"Not Found","description":"HTTP 404 Not Found"}}}"#),
        (503, #"{"chart":{"result":null,"error":{"code":"Internal Server Error","description":"busy"}}}"#),
    ])
    func otherFailuresReportTheHTTPStatus(_ status: Int, _ body: String) {
        #expect(throws: QuoteError.httpStatus(status)) {
            try QuoteService.parse(Data(body.utf8), statusCode: status)
        }
    }

    @Test(arguments: [
        "",
        "not json",
        #"{"chart":{"result":[],"error":null}}"#,
        #"{"chart":{"result":null,"error":null}}"#,
        #"{"chart":{"result":[{"meta":{"currency":"USD"}}],"error":null}}"#,  // no symbol
        #"{"chart":{"result":null,"error":{"code":"Bad Request","description":"x"}}}"#,
    ])
    func unreadableChartIsBadResponse(_ body: String) {
        #expect(throws: QuoteError.badResponse) { try QuoteService.parse(Data(body.utf8)) }
    }
}
