import Foundation

/// Decides when a shown price is too old to trust (issue #9, docs/adr/0011).
///
/// Every function here is pure and takes the current time as a parameter, so
/// tests can pass any clock they like.
enum Staleness {
    /// A quote is never stale sooner than this, even with a short poll interval.
    static let minimumThreshold: TimeInterval = 5 * 60

    /// How old the last good update may get before the quote counts as stale:
    /// two missed polls, but at least `minimumThreshold`.
    static func threshold(pollInterval: TimeInterval) -> TimeInterval {
        max(2 * pollInterval, minimumThreshold)
    }

    /// Whether a symbol's quote is stale at `now`.
    ///
    /// - Parameters:
    ///   - lastUpdate: when the app last received good data for the symbol (a
    ///     successful poll or a stream tick), by the local clock. `nil` means
    ///     there is no quote yet, which is "loading" or "err", not stale.
    ///   - isLive: whether the symbol is streaming (docs/adr/0005). A live symbol is never stale.
    ///   - pollInterval: the user's refresh interval.
    static func isStale(lastUpdate: Date?, isLive: Bool, pollInterval: TimeInterval, now: Date) -> Bool {
        guard let lastUpdate, !isLive else { return false }
        return now.timeIntervalSince(lastUpdate) > threshold(pollInterval: pollInterval)
    }

    /// A short description of why a poll failed, for the menu ("timeout", "offline", "HTTP 503").
    static func errorSummary(_ error: Error) -> String {
        switch error {
        case QuoteError.notFound:
            return "symbol not found"
        case QuoteError.badResponse:
            return "no price in response"
        case QuoteError.httpStatus(let status):
            return "HTTP \(status)"
        case let error as URLError:
            switch error.code {
            case .timedOut:
                return "timeout"
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "offline"
            case .cannotFindHost, .dnsLookupFailed:
                return "host not found"
            case .cannotConnectToHost:
                return "cannot connect"
            default:
                return "network error \(error.code.rawValue)"
            }
        default:
            return error.localizedDescription
        }
    }

    /// The menu lines that describe how fresh a quote is.
    ///
    /// - Fresh: "Updated 14:02:11", plus "Last error: …" if the latest poll failed.
    /// - Stale: "Stale: last update 14:02:11", plus "Last error: …" when known.
    static func menuLines(updatedAt: Date, lastUpdate: Date?, lastError: String?, isStale: Bool,
                          formatTime: (Date) -> String) -> [String] {
        var lines: [String]
        if isStale {
            lines = ["Stale: last update \(formatTime(lastUpdate ?? updatedAt))"]
        } else {
            lines = ["Updated \(formatTime(updatedAt))"]
        }
        if let lastError {
            lines.append("Last error: \(lastError)")
        }
        return lines
    }
}
