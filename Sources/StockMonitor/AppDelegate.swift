import AppKit
import Network

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Keys {
        static let symbols = "symbols"
        static let showPercent = "showPercent"
        static let interval = "refreshInterval"
    }

    private let defaults = UserDefaults.standard
    private var items: [String: NSStatusItem] = [:]
    private var quotes: [String: Quote] = [:]
    /// Why the latest poll failed, per symbol (short text such as "timeout").
    /// Cleared by the next successful poll or stream tick.
    private var lastError: [String: String] = [:]
    /// When good data last arrived for each symbol, by the local clock (issue #9).
    /// Drives the stale state; see `Staleness`.
    private var lastUpdate: [String: Date] = [:]
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

    // Recovery after sleep or network loss (issue #5). The stream reconnects on
    // its own; this makes sure polled symbols catch up too.
    private lazy var recoveryRefresh = RefreshTrigger { [weak self] in
        self?.refresh(force: true)
        self?.scheduleTimer()
    }
    private var wakeObserver: NSObjectProtocol?
    private let pathMonitor = NWPathMonitor()
    private var lastPathStatus: NWPath.Status?

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
        observeWakeAndNetwork()
    }

    private func observeWakeAndNetwork() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.recoveryRefresh.fire() }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if RefreshTrigger.connectionRestored(from: lastPathStatus, to: path.status) {
                recoveryRefresh.fire()
            }
            lastPathStatus = path.status
        }
        pathMonitor.start(queue: .main)
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
            lastUpdate[sym] = nil
            lastError[sym] = nil
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
        let stale = q != nil && isStale(sym)
        let price = q.map { Formatting.price($0.price) } ?? (lastError[sym] != nil ? "err" : "…")
        var change: String?
        if let q {
            change = showPercent
                ? Formatting.percent(q.changePercent)
                : Formatting.change(q.change)
        }
        button.image = TickerImage.make(symbol: sym, price: price, change: change,
                                        isUp: (q?.change ?? 0) >= 0, isStale: stale)
        button.toolTip = q.map { q in
            ([q.name] + freshnessLines(sym, quote: q, stale: stale)).joined(separator: "\n")
        } ?? sym
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

    private func isStale(_ sym: String) -> Bool {
        Staleness.isStale(lastUpdate: lastUpdate[sym], isLive: isLive(sym), pollInterval: interval, now: Date())
    }

    /// "Updated …" or "Stale: last update …", plus the last error if there is one.
    private func freshnessLines(_ sym: String, quote: Quote, stale: Bool) -> [String] {
        Staleness.menuLines(updatedAt: quote.fetchedAt, lastUpdate: lastUpdate[sym], lastError: lastError[sym],
                            isStale: stale) { $0.formatted(date: .omitted, time: .standard) }
    }

    @objc private func refreshNow() {
        refresh(force: true)
    }

    /// Polls symbols over HTTP. Live (streaming) symbols are only polled every
    /// `livePollInterval` unless `force` is set.
    private func refresh(force: Bool) {
        let now = Date()
        // Re-check staleness on every tick, so a quote turns gray even if its poll hangs.
        symbols.forEach(render)
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
                        quotes[sym] = current.withMetadata(from: polled)
                    } else {
                        quotes[sym] = polled
                    }
                    lastUpdate[sym] = Date()
                    lastError[sym] = nil
                } catch {
                    // Record the failure even when an older quote is still shown,
                    // so the menu can say why the price stopped updating.
                    lastError[sym] = Staleness.errorSummary(error)
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

        quotes[sym] = Quote.applying(tick, to: previous)
        lastTickReceived[sym] = Date()
        lastUpdate[sym] = Date()
        lastError[sym] = nil
        render(sym)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let sym = items.first(where: { $0.value.menu === menu })?.key else { return }

        if let q = quotes[sym] {
            menu.addItem(disabled(q.name, bold: true))
            menu.addItem(disabled("\(Formatting.price(q.price)) \(q.currency ?? "")"))
            menu.addItem(disabled("\(Formatting.change(q.change)) (\(Formatting.percent(q.changePercent)))"))
            menu.addItem(disabled("Prev close \(Formatting.price(q.previousClose))"))
            freshnessLines(sym, quote: q, stale: isStale(sym)).forEach { menu.addItem(disabled($0)) }
        } else {
            menu.addItem(disabled(lastError[sym].map { "\(sym): failed to load (\($0))" } ?? "\(sym): loading…"))
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
        // The dialog checks the symbol with Yahoo and only returns one that has a quote.
        guard let added = AddSymbolDialog.run(existing: symbols) else { return }
        let sym = added.symbol
        symbols.append(sym)
        // Use the quote from the check so the new item shows its price immediately.
        quotes[sym] = added.quote
        lastPoll[sym] = added.quote.fetchedAt
        lastUpdate[sym] = added.quote.fetchedAt
        lastError[sym] = nil
        // Rebuild all items so menu bar order matches the list order.
        items.values.forEach { NSStatusBar.system.removeStatusItem($0) }
        items.removeAll()
        syncStatusItems()
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
        // The stale threshold depends on the interval.
        symbols.forEach(render)
    }
}
