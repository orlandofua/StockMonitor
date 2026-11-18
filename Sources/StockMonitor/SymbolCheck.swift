import Foundation

/// Checks a symbol the user typed against Yahoo before it is added (issue #6),
/// so a typo does not become a menu bar item that shows "err" for good.
enum SymbolCheck {
    enum Outcome {
        /// Nothing was typed.
        case empty
        /// The symbol is already in the menu bar.
        case duplicate(String)
        /// Yahoo returned a quote. Add `symbol` and show `quote` right away.
        case valid(symbol: String, quote: Quote)
        /// The symbol cannot be added. `message` is shown in the dialog.
        case failed(symbol: String, message: String)
    }

    static let notFoundMessage = "Symbol not found."

    /// The form symbols are stored in: trimmed and uppercased.
    static func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Normalizes `input` and, unless it is empty or already in `existing`, fetches it once.
    static func check(_ input: String, existing: [String],
                      fetch: (String) async throws -> Quote) async -> Outcome {
        let symbol = normalize(input)
        guard !symbol.isEmpty else { return .empty }
        guard !existing.contains(symbol) else { return .duplicate(symbol) }
        do {
            return .valid(symbol: symbol, quote: try await fetch(symbol))
        } catch {
            return .failed(symbol: symbol, message: message(for: error))
        }
    }

    /// What the dialog says when the check fails. A missing symbol and a failed
    /// connection get different messages, because only the first means "fix the ticker".
    static func message(for error: Error) -> String {
        switch error {
        case QuoteError.notFound:
            return notFoundMessage
        case QuoteError.httpStatus(let status):
            return "Yahoo Finance answered with an error (HTTP \(status)). Try again later."
        case QuoteError.badResponse:
            return "Yahoo Finance did not return a price for this symbol. Try again later."
        case is URLError:
            return "Couldn't reach Yahoo Finance. Check your connection and try again."
        default:
            return "Couldn't check the symbol: \(error.localizedDescription)"
        }
    }
}
