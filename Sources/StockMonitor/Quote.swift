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

enum QuoteError: Error {
    case badResponse
}

/// Fetches quotes from Yahoo Finance's public chart endpoint.
enum QuoteService {
    static func fetch(_ symbol: String) async throws -> Quote {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "=^/"))) ?? symbol
        let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw QuoteError.badResponse }

        struct Envelope: Decodable {
            struct Chart: Decodable { let result: [Result]? }
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
            let chart: Chart
        }

        let meta = try JSONDecoder().decode(Envelope.self, from: data).chart.result?.first?.meta
        guard let meta, let price = meta.regularMarketPrice else { throw QuoteError.badResponse }
        return Quote(
            symbol: meta.symbol,
            name: meta.shortName ?? meta.longName ?? meta.symbol,
            price: price,
            previousClose: meta.previousClose ?? meta.chartPreviousClose ?? price,
            currency: meta.currency,
            fetchedAt: Date()
        )
    }
}
