import Foundation
import Testing
@testable import StockMonitor

@Suite("Symbol check before adding")
struct SymbolCheckTests {
    static let quote = Quote(symbol: "AAPL", name: "Apple Inc.", price: 354.3, previousClose: 352.78,
                             currency: "USD", fetchedAt: Date(timeIntervalSince1970: 1_794_929_270))

    /// Records the symbols it was asked for and answers with `answer`.
    final class FakeFetch {
        var requested: [String] = []
        let answer: Result<Quote, Error>
        init(_ answer: Result<Quote, Error>) { self.answer = answer }
        func fetch(_ symbol: String) async throws -> Quote {
            requested.append(symbol)
            return try answer.get()
        }
    }

    // MARK: Acceptance criteria

    @Test func unknownSymbolIsNotFound() async {
        let fake = FakeFetch(.failure(QuoteError.notFound))
        let outcome = await SymbolCheck.check("APPL.X", existing: ["BZ=F"], fetch: fake.fetch)
        guard case .failed(let symbol, let message) = outcome else {
            Issue.record("expected .failed, got \(outcome)"); return
        }
        #expect(symbol == "APPL.X")
        #expect(message == "Symbol not found.")
    }

    @Test func validSymbolReturnsItsQuote() async {
        let fake = FakeFetch(.success(Self.quote))
        let outcome = await SymbolCheck.check("AAPL", existing: ["BZ=F"], fetch: fake.fetch)
        guard case .valid(let symbol, let quote) = outcome else {
            Issue.record("expected .valid, got \(outcome)"); return
        }
        #expect(symbol == "AAPL")
        #expect(quote.price == 354.3)
        #expect(quote.name == "Apple Inc.")
    }

    @Test(arguments: [URLError.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost])
    func networkFailureHasItsOwnMessage(code: URLError.Code) async {
        let fake = FakeFetch(.failure(URLError(code)))
        let outcome = await SymbolCheck.check("AAPL", existing: [], fetch: fake.fetch)
        guard case .failed(_, let message) = outcome else {
            Issue.record("expected .failed, got \(outcome)"); return
        }
        #expect(message != SymbolCheck.notFoundMessage)
        #expect(message.contains("Couldn't reach Yahoo Finance"))
    }

    // MARK: Input handling

    @Test func inputIsTrimmedAndUppercasedBeforeFetching() async {
        let fake = FakeFetch(.success(Self.quote))
        let outcome = await SymbolCheck.check("  bz=f \n", existing: [], fetch: fake.fetch)
        #expect(fake.requested == ["BZ=F"])
        guard case .valid(let symbol, _) = outcome else {
            Issue.record("expected .valid, got \(outcome)"); return
        }
        #expect(symbol == "BZ=F")
    }

    @Test func emptyInputIsNotFetched() async {
        let fake = FakeFetch(.success(Self.quote))
        let outcome = await SymbolCheck.check("   ", existing: [], fetch: fake.fetch)
        guard case .empty = outcome else { Issue.record("expected .empty, got \(outcome)"); return }
        #expect(fake.requested.isEmpty)
    }

    @Test func duplicateIsNotFetched() async {
        let fake = FakeFetch(.success(Self.quote))
        let outcome = await SymbolCheck.check("aapl", existing: ["BZ=F", "AAPL"], fetch: fake.fetch)
        guard case .duplicate(let symbol) = outcome else {
            Issue.record("expected .duplicate, got \(outcome)"); return
        }
        #expect(symbol == "AAPL")
        #expect(fake.requested.isEmpty)
    }

    // MARK: Messages

    @Test func serverErrorsAreNotReportedAsNotFound() {
        let http = SymbolCheck.message(for: QuoteError.httpStatus(503))
        let bad = SymbolCheck.message(for: QuoteError.badResponse)
        #expect(http.contains("HTTP 503"))
        #expect(http != SymbolCheck.notFoundMessage)
        #expect(bad != SymbolCheck.notFoundMessage)
    }

    @Test func messagesForDifferentFailuresDiffer() {
        let messages = [
            SymbolCheck.message(for: QuoteError.notFound),
            SymbolCheck.message(for: URLError(.notConnectedToInternet)),
            SymbolCheck.message(for: QuoteError.httpStatus(500)),
            SymbolCheck.message(for: QuoteError.badResponse),
        ]
        #expect(Set(messages).count == messages.count)
    }
}
