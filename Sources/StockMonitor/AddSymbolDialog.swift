import AppKit

/// The "Add Symbol" alert. Clicking Add checks the symbol with Yahoo while the
/// dialog stays open; it only closes on a valid symbol or on Cancel (issue #6).
final class AddSymbolDialog: NSObject {
    private static let prompt = "Enter a Yahoo Finance ticker (e.g. AAPL, BZ=F, BTC-USD, ^GSPC)."

    private let existing: [String]
    private let alert = NSAlert()
    private let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    private var addButton: NSButton?
    private var check: Task<Void, Never>?
    private var result: (symbol: String, quote: Quote)?

    init(existing: [String]) {
        self.existing = existing
    }

    /// Shows the dialog modally. Returns the checked symbol and its quote, or nil on Cancel.
    func run() -> (symbol: String, quote: Quote)? {
        alert.messageText = "Add Symbol"
        alert.informativeText = Self.prompt
        field.placeholderString = "Symbol"
        alert.accessoryView = field

        let add = alert.addButton(withTitle: "Add")
        // Replace NSAlert's default action, which would close the dialog before the check.
        add.target = self
        add.action = #selector(addClicked)
        addButton = add
        alert.addButton(withTitle: "Cancel")

        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        check?.cancel()
        return result
    }

    @objc private func addClicked() {
        guard check == nil else { return }
        let input = field.stringValue
        let existing = existing
        setChecking(true, text: "Checking \(SymbolCheck.normalize(input)) with Yahoo Finance…")

        check = Task { @MainActor [weak self] in
            let outcome = await SymbolCheck.check(input, existing: existing, fetch: QuoteService.fetch)
            guard let self, !Task.isCancelled else { return }
            check = nil
            switch outcome {
            case .valid(let symbol, let quote):
                result = (symbol, quote)
                NSApp.stopModal(withCode: .alertFirstButtonReturn)
            case .empty:
                setChecking(false, text: Self.prompt)
            case .duplicate(let symbol):
                setChecking(false, text: "\(symbol) is already in the menu bar.")
            case .failed(let symbol, let message):
                setChecking(false, text: "\(symbol): \(message)")
            }
        }
    }

    private func setChecking(_ checking: Bool, text: String) {
        alert.informativeText = text
        addButton?.isEnabled = !checking
        field.isEnabled = !checking
        alert.layout()
        if !checking {
            alert.window.makeFirstResponder(field)
            field.selectText(nil)
        }
    }
}
