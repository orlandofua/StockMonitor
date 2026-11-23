import AppKit
import Network

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Keys {
        static let symbols = "symbols"
        static let showPercent = "showPercent"
        static let interval = "refreshInterval"
    }

    private let defaults = UserDefaults.standard
    /// The only per-symbol state kept here: what is drawn in the menu bar (docs/adr/0004).
    private var items: [String: NSStatusItem] = [:]
    /// The ticker state of every tracked symbol, and the rules that act on it
    /// (issue #42, GLOSSARY.md).
    private lazy var tickers = TickerState(symbols: symbols)
    /// Each symbol's comparison period (issue #16, docs/adr/0014).
    private lazy var periods = ComparePeriodStore(defaults: defaults)
    private var timer: Timer?
    /// One-shot timer that redraws tickers when the next quote crosses the stale
    /// threshold, so the menu bar does not wait for the poll timer. Never polls.
    private var staleTimer: Timer?

    // Live streaming (see docs/adr/0005). Polling remains the fallback.
    private let stream = QuoteStream()

    // Recovery after sleep or network loss (issue #5). The stream reconnects on
    // its own; this makes sure polled symbols catch up too.
    private lazy var recoveryRefresh = RefreshTrigger { [weak self] in
        self?.refresh(force: true)
        self?.scheduleTimer()
    }
    private var wakeObserver: NSObjectProtocol?
    private let launchAtLogin = LaunchAtLogin()
    /// In-app updates (issue #30, ADR 0015). Off, with no menu items, when the
    /// build has no update feed.
    private var updates: Updates?
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
        updates = Updates(info: Bundle.main.infoDictionary)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        staleTimer?.invalidate()
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
        guard let button = items[sym]?.button, let view = tickerView(sym) else { return }
        button.image = TickerImage.make(symbol: sym, price: view.priceText, change: view.badge?.text,
                                        isUp: view.badge?.isUp ?? true, isStale: view.isStale,
                                        period: view.badge?.periodLabel)
        button.toolTip = view.tooltipLines.joined(separator: "\n")
    }

    // MARK: Refresh

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh(force: false) }
        // The stale threshold depends on the interval.
        scheduleStaleCheck(reset: true)
    }

    /// Schedules a redraw for the moment the next quote turns stale (issue #9).
    ///
    /// Without `reset`, an already scheduled check is kept when it fires no later
    /// than needed. Update times only move forward, so firing early is harmless:
    /// the handler redraws and schedules again.
    private func scheduleStaleCheck(reset: Bool = false) {
        let next = tickers.nextStaleRecheck(now: Date(), pollInterval: interval)
        if !reset, let current = staleTimer, current.isValid, let next, current.fireDate <= next { return }
        staleTimer?.invalidate()
        staleTimer = nil
        guard let next else { return }
        let check = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            symbols.forEach(render)
            scheduleStaleCheck(reset: true)
        }
        // Common modes, so the ticker still turns gray while a menu is open.
        RunLoop.main.add(check, forMode: .common)
        staleTimer = check
    }

    /// What the symbol's ticker and menu show now.
    private func tickerView(_ sym: String) -> TickerState.View? {
        tickers.view(sym, now: Date(), pollInterval: interval, pollIntervalLabel: intervalLabel(interval),
                     period: periods.period(for: sym), showPercent: showPercent)
    }

    /// Runs the history requests ticker state asks for, for the given symbols
    /// at their stored comparison periods, and reports the results back.
    private func loadBaselines(for syms: [String]) {
        let wanted = Dictionary(syms.map { ($0, periods.period(for: $0)) }, uniquingKeysWith: { first, _ in first })
        for fetch in tickers.baselinesToFetch(now: Date(), periods: wanted) {
            Task { @MainActor in
                do {
                    let history = try await QuoteService.fetchHistory(fetch.symbol, range: fetch.range)
                    tickers.baselineFetched(fetch.symbol, period: fetch.period, history: history, at: Date())
                } catch {
                    tickers.baselineFetchFailed(fetch.symbol, period: fetch.period, error: error)
                }
                render(fetch.symbol)
            }
        }
    }

    @objc private func refreshNow() {
        refresh(force: true)
    }

    /// Polls the symbols ticker state says are due. `force` polls every symbol,
    /// live or not.
    private func refresh(force: Bool) {
        let now = Date()
        // Re-check staleness on every tick, so a quote turns gray even if its poll hangs.
        symbols.forEach(render)
        loadBaselines(for: symbols)
        for sym in tickers.symbolsToPoll(now: now, force: force) {
            tickers.pollStarted(sym, at: now)
            Task { @MainActor in
                do {
                    // While the symbol is live, ticker state keeps the streamed price.
                    tickers.pollSucceeded(try await QuoteService.fetch(sym), at: Date())
                    scheduleStaleCheck()
                } catch {
                    // Record the failure even when an older quote is still shown,
                    // so the menu can say why the price stopped updating.
                    tickers.pollFailed(sym, error: error)
                }
                render(sym)
            }
        }
    }

    /// Ticker state applies the merge, out-of-order and untracked-symbol rules.
    private func handle(_ tick: StreamTick) {
        tickers.tickReceived(tick, at: Date())
        scheduleStaleCheck()
        render(tick.symbol)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let sym = items.first(where: { $0.value.menu === menu })?.key else { return }

        if let view = tickerView(sym) {
            if let title = view.menuTitle { menu.addItem(disabled(title, bold: true)) }
            view.menuLines.forEach { menu.addItem(disabled($0)) }
            menu.addItem(disabled(view.statusLine))
        }
        menu.addItem(.separator())

        menu.addItem(action("Refresh Now", #selector(refreshNow), key: "r"))
        menu.addItem(action("Add Symbol…", #selector(addSymbol), key: "n"))
        let remove = action("Remove \(sym)", #selector(removeSymbol(_:)))
        remove.representedObject = sym
        menu.addItem(remove)

        let pct = action("Show Percent Change", #selector(togglePercent))
        pct.state = showPercent ? .on : .off
        menu.addItem(pct)

        let compareItem = NSMenuItem(title: "Compare To", action: nil, keyEquivalent: "")
        let compareMenu = NSMenu()
        let current = periods.period(for: sym)
        for period in ComparePeriod.allCases {
            let i = action(period.label, #selector(setComparePeriod(_:)))
            i.representedObject = [sym, period.rawValue]
            i.state = period == current ? .on : .off
            compareMenu.addItem(i)
        }
        compareItem.submenu = compareMenu
        menu.addItem(compareItem)

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

        // Read from the system each time the menu opens, so changes made in
        // System Settings show up here too (issue #10).
        let login = action(LaunchAtLogin.title, #selector(toggleLaunchAtLogin))
        login.state = launchAtLogin.menuState
        login.toolTip = launchAtLogin.toolTip
        menu.addItem(login)
        updates?.menuItems().forEach(menu.addItem)

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
        tickers.add(added.quote)
        // Rebuild all items so menu bar order matches the list order.
        items.values.forEach { NSStatusBar.system.removeStatusItem($0) }
        items.removeAll()
        syncStatusItems()
        // The new quote may turn stale before any pending check fires.
        scheduleStaleCheck()
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
            periods.remove(sym)
            tickers.remove(sym)
            symbols = []
            NSApp.terminate(nil)
            return
        }
        symbols.removeAll { $0 == sym }
        periods.remove(sym)
        tickers.remove(sym)
        syncStatusItems()
        // Drop a check that was only waiting for the removed symbol.
        scheduleStaleCheck(reset: true)
    }

    @objc private func setComparePeriod(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let period = ComparePeriod(rawValue: pair[1]) else { return }
        let sym = pair[0]
        periods.set(period, for: sym)
        // Redraw now (1D, or a cached baseline, shows right away), then fetch
        // history if needed. Switching to 1D drops a request still in flight.
        render(sym)
        loadBaselines(for: [sym])
    }

    @objc private func togglePercent() {
        showPercent.toggle()
        symbols.forEach(render)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchAtLogin.toggle()
        } catch {
            // toggle() only throws Failure; anything else is reported as a failed add.
            let failure = error as? LaunchAtLogin.Failure ?? LaunchAtLogin.Failure(action: .register, underlying: error)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = failure.message
            alert.informativeText = failure.informativeText
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? Double else { return }
        interval = secs
        scheduleTimer()
        // The stale threshold depends on the interval; redraw now, and
        // scheduleTimer has moved the stale check to the new threshold.
        symbols.forEach(render)
    }
}
