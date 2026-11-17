import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Keys {
        static let symbols = "symbols"
        static let showPercent = "showPercent"
        static let interval = "refreshInterval"
    }

    private let defaults = UserDefaults.standard
    private var items: [String: NSStatusItem] = [:]
    private var quotes: [String: Quote] = [:]
    private var errors: Set<String> = []
    private var timer: Timer?

    // Live streaming (see docs/adr/0005). Polling remains the fallback.
    private let stream = QuoteStream()
    /// When the last stream tick was received, per symbol. Drives the "live" state.
    private var lastTickReceived: [String: Date] = [:]
    /// When each symbol was last polled over HTTP.
    private var lastPoll: [String: Date] = [:]
    /// A symbol counts as live if a tick arrived within this window.
    private let liveWindow: TimeInterval = 120
    /// Live symbols are still polled this often to refresh name and previous close.
    private let livePollInterval: TimeInterval = 300

    private var symbols: [String] {
        get {
            // An empty list falls back to the default so the app never runs with no menu bar item.
            let stored = defaults.stringArray(forKey: Keys.symbols) ?? []
            return stored.isEmpty ? ["BZ=F"] : stored
        }
        set { defaults.set(newValue, forKey: Keys.symbols) }
    }
    private var showPercent: Bool {
        get { defaults.bool(forKey: Keys.showPercent) }
        set { defaults.set(newValue, forKey: Keys.showPercent) }
    }
    private var interval: TimeInterval {
        get { let v = defaults.double(forKey: Keys.interval); return v > 0 ? v : 60 }
        set { defaults.set(newValue, forKey: Keys.interval) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        stream.onTick = { [weak self] tick in self?.handle(tick) }
        syncStatusItems()
        refresh(force: true)
        scheduleTimer()
    }

    // MARK: Status items

    private func syncStatusItems() {
        let wanted = symbols
        for (sym, item) in items where !wanted.contains(sym) {
            NSStatusBar.system.removeStatusItem(item)
            items[sym] = nil
            quotes[sym] = nil
            lastTickReceived[sym] = nil
            lastPoll[sym] = nil
        }
        stream.setSymbols(wanted)
        // Create in reverse so the first symbol ends up leftmost.
        for sym in wanted.reversed() where items[sym] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.imagePosition = .imageOnly
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            items[sym] = item
            render(sym)
        }
    }

    private func render(_ sym: String) {
        guard let button = items[sym]?.button else { return }
        let q = quotes[sym]
        let price = q.map { format($0.price) } ?? (errors.contains(sym) ? "err" : "…")
        var change: String?
        if let q {
            change = showPercent
                ? String(format: "%+.2f%%", q.changePercent)
                : formatChange(q.change)
        }
        button.image = TickerImage.make(symbol: sym, price: price, change: change, isUp: (q?.change ?? 0) >= 0)
        button.toolTip = q.map { "\($0.name)\nUpdated \($0.fetchedAt.formatted(date: .omitted, time: .standard))" } ?? sym
    }

    /// Point change, always rounded to 2 decimals with explicit sign (e.g. +0.26, -1.05).
    private func formatChange(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return (rounded >= 0 ? "+" : "") + format(rounded, decimals: 2)
    }

    private func format(_ value: Double, decimals fixed: Int? = nil) -> String {
        let decimals = fixed ?? (abs(value) >= 1 || value == 0 ? 2 : 4)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: Refresh

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh(force: false) }
    }

    private func isLive(_ sym: String) -> Bool {
        guard let last = lastTickReceived[sym] else { return false }
        return Date().timeIntervalSince(last) < liveWindow
    }

    @objc private func refreshNow() {
        refresh(force: true)
    }

    /// Polls symbols over HTTP. Live (streaming) symbols are only polled every
    /// `livePollInterval` unless `force` is set.
    private func refresh(force: Bool) {
        let now = Date()
        for sym in symbols {
            if !force, isLive(sym), let polled = lastPoll[sym], now.timeIntervalSince(polled) < livePollInterval {
                continue
            }
            lastPoll[sym] = now
            Task { @MainActor in
                do {
                    let polled = try await QuoteService.fetch(sym)
                    // If the stream is live, its price is fresher than the poll's.
                    // Keep it and take only the metadata from the poll.
                    if isLive(sym), let current = quotes[sym] {
                        quotes[sym] = Quote(symbol: sym, name: polled.name, price: current.price,
                                            previousClose: polled.previousClose, currency: polled.currency,
                                            fetchedAt: current.fetchedAt)
                    } else {
                        quotes[sym] = polled
                    }
                    errors.remove(sym)
                } catch {
                    if quotes[sym] == nil { errors.insert(sym) }
                }
                render(sym)
            }
        }
    }

    private func handle(_ tick: StreamTick) {
        let sym = tick.symbol
        guard items[sym] != nil else { return }
        let previous = quotes[sym]
        // Ignore out-of-order ticks.
        if let previous, isLive(sym), tick.time < previous.fetchedAt { return }

        let previousClose = previous?.previousClose
            ?? tick.previousClose
            ?? tick.change.map { tick.price - $0 }
            ?? tick.price
        quotes[sym] = Quote(symbol: sym, name: previous?.name ?? sym, price: tick.price,
                            previousClose: previousClose, currency: previous?.currency,
                            fetchedAt: tick.time)
        lastTickReceived[sym] = Date()
        errors.remove(sym)
        render(sym)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let sym = items.first(where: { $0.value.menu === menu })?.key else { return }

        if let q = quotes[sym] {
            menu.addItem(disabled(q.name, bold: true))
            menu.addItem(disabled("\(format(q.price)) \(q.currency ?? "")"))
            menu.addItem(disabled(String(format: "%@ (%+.2f%%)", formatChange(q.change), q.changePercent)))
            menu.addItem(disabled("Prev close \(format(q.previousClose))"))
            menu.addItem(disabled("Updated \(q.fetchedAt.formatted(date: .omitted, time: .standard))"))
        } else {
            menu.addItem(disabled(errors.contains(sym) ? "\(sym): failed to load" : "\(sym): loading…"))
        }
        menu.addItem(disabled(isLive(sym) ? "● Live (streaming)" : "Polling every \(intervalLabel(interval))"))
        menu.addItem(.separator())

        menu.addItem(action("Refresh Now", #selector(refreshNow), key: "r"))
        menu.addItem(action("Add Symbol…", #selector(addSymbol), key: "n"))
        let remove = action("Remove \(sym)", #selector(removeSymbol(_:)))
        remove.representedObject = sym
        menu.addItem(remove)

        let pct = action("Show Percent Change", #selector(togglePercent))
        pct.state = showPercent ? .on : .off
        menu.addItem(pct)

        let intervalItem = NSMenuItem(title: "Refresh Every", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, secs) in Self.intervals {
            let i = action(label, #selector(setInterval(_:)))
            i.representedObject = secs
            i.state = secs == interval ? .on : .off
            sub.addItem(i)
        }
        intervalItem.submenu = sub
        menu.addItem(intervalItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private static let intervals: [(String, TimeInterval)] = [
        ("15 seconds", 15), ("30 seconds", 30), ("1 minute", 60), ("5 minutes", 300),
    ]

    private func intervalLabel(_ secs: TimeInterval) -> String {
        Self.intervals.first { $0.1 == secs }?.0 ?? "\(Int(secs)) seconds"
    }

    private func disabled(_ title: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if bold {
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        }
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func addSymbol() {
        let alert = NSAlert()
        alert.messageText = "Add Symbol"
        alert.informativeText = "Enter a Yahoo Finance ticker (e.g. AAPL, BZ=F, BTC-USD, ^GSPC)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Symbol"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let sym = field.stringValue.trimmingCharacters(in: .whitespaces).uppercased()
        guard !sym.isEmpty, !symbols.contains(sym) else { return }
        symbols.append(sym)
        // Rebuild all items so menu bar order matches the list order.
        items.values.forEach { NSStatusBar.system.removeStatusItem($0) }
        items.removeAll()
        syncStatusItems()
        refresh(force: true)
    }

    @objc private func removeSymbol(_ sender: NSMenuItem) {
        guard let sym = sender.representedObject as? String else { return }
        if symbols.count == 1 {
            let alert = NSAlert()
            alert.messageText = "Removing the last symbol will quit StockMonitor."
            alert.addButton(withTitle: "Remove & Quit")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            symbols = []
            NSApp.terminate(nil)
            return
        }
        symbols.removeAll { $0 == sym }
        syncStatusItems()
    }

    @objc private func togglePercent() {
        showPercent.toggle()
        symbols.forEach(render)
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? Double else { return }
        interval = secs
        scheduleTimer()
    }
}
