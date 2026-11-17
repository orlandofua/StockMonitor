import Foundation

struct Quote {
    let symbol: String
    let name: String
    let price: Double
    let previousClose: Double
    let currency: String?
    let fetchedAt: Date

    var change: Double { price - previousClose }
    var changePercent: Double { previousClose == 0 ? 0 : change / previousClose * 100 }
}

/// Why a poll did not produce a quote. Transport failures (offline, timeout)
/// are not wrapped: `fetch` rethrows them as the `URLError` from `URLSession`.
enum QuoteError: Error, Equatable {
    /// Yahoo has no data for the symbol: it does not exist or is delisted.
    case notFound
    /// The response was not a chart with a price (unreadable JSON, no result, no price).
    case badResponse
    /// The server answered with this non-200 status and no chart error in the body.
    case httpStatus(Int)
}

/// Fetches quotes from Yahoo Finance's public chart endpoint.
enum QuoteService {
    static func fetch(_ symbol: String) async throws -> Quote {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "=^/"))) ?? symbol
        let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try parse(data, statusCode: status)
    }

    /// Turns a chart endpoint response into a quote (see docs/adr/0003).
    ///
    /// Yahoo answers an unknown symbol with HTTP 404 and a body like
    /// `{"chart":{"result":null,"error":{"code":"Not Found",...}}}`, so the body is
    /// checked for a chart error before the status code.
    static func parse(_ data: Data, statusCode: Int = 200, fetchedAt: Date = Date()) throws -> Quote {
        let chart = try? JSONDecoder().decode(Envelope.self, from: data).chart
        if let error = chart?.error {
            throw error.code == "Not Found" ? QuoteError.notFound
                : statusCode == 200 ? QuoteError.badResponse : QuoteError.httpStatus(statusCode)
        }
        guard statusCode == 200 else { throw QuoteError.httpStatus(statusCode) }
        guard let meta = chart?.result?.first?.meta, let price = meta.regularMarketPrice else {
            throw QuoteError.badResponse
        }
        return Quote(
            symbol: meta.symbol,
            name: meta.shortName ?? meta.longName ?? meta.symbol,
            price: price,
            previousClose: meta.previousClose ?? meta.chartPreviousClose ?? price,
            currency: meta.currency,
            fetchedAt: fetchedAt
        )
    }

    private struct Envelope: Decodable {
        struct Chart: Decodable {
            let result: [Result]?
            let error: ChartError?

            enum CodingKeys: String, CodingKey { case result, error }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                result = try container.decodeIfPresent([Result].self, forKey: .result)
                // Only an object with a code counts as an error. Any other shape is
                // ignored so it cannot hide a valid result.
                error = try? container.decodeIfPresent(ChartError.self, forKey: .error)
            }
        }
        struct Result: Decodable { let meta: Meta }
        struct Meta: Decodable {
            let symbol: String
            let shortName: String?
            let longName: String?
            let currency: String?
            let regularMarketPrice: Double?
            let chartPreviousClose: Double?
            let previousClose: Double?
        }
        struct ChartError: Decodable {
            let code: String
            let description: String?
        }
        let chart: Chart
    }
}

// MARK: Merging stream and poll data (see docs/adr/0005)

extension Quote {
    /// Builds the quote that results from applying a stream tick on top of `previous`.
    /// The previous close comes from the earlier quote when known (polls are authoritative),
    /// otherwise from the tick itself.
    static func applying(_ tick: StreamTick, to previous: Quote?) -> Quote {
        let previousClose = previous?.previousClose
            ?? tick.previousClose
            ?? tick.change.map { tick.price - $0 }
            ?? tick.price
        return Quote(symbol: tick.symbol, name: previous?.name ?? tick.symbol, price: tick.price,
                     previousClose: previousClose, currency: previous?.currency, fetchedAt: tick.time)
    }

    /// Keeps this (streamed, fresher) price and time, taking name, currency and previous close from a poll.
    func withMetadata(from polled: Quote) -> Quote {
        Quote(symbol: symbol, name: polled.name, price: price, previousClose: polled.previousClose,
              currency: polled.currency, fetchedAt: fetchedAt)
    }
}
