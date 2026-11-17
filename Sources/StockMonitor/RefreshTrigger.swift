import Foundation
import Network

/// Turns wake and network-recovery events into a single delayed refresh.
///
/// The first event schedules the action after `delay` (so Wi-Fi has time to
/// reconnect after wake). Events that arrive while a refresh is already pending
/// are absorbed by it, so a burst of events causes one refresh, not several.
final class RefreshTrigger {
    /// Schedules `work` after a delay and returns a function that cancels it.
    typealias Scheduler = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void

    private let delay: TimeInterval
    private let schedule: Scheduler
    private let action: () -> Void
    private var cancelPending: (() -> Void)?

    init(delay: TimeInterval = 2, schedule: @escaping Scheduler = RefreshTrigger.mainQueue, action: @escaping () -> Void) {
        self.delay = delay
        self.schedule = schedule
        self.action = action
    }

    deinit { cancelPending?() }

    var isPending: Bool { cancelPending != nil }

    /// Requests a refresh. Does nothing if one is already scheduled.
    func fire() {
        guard cancelPending == nil else { return }
        cancelPending = schedule(delay) { [weak self] in
            guard let self else { return }
            self.cancelPending = nil
            self.action()
        }
    }

    /// Whether a network path update means the connection just came back.
    ///
    /// `previous` is nil for the first update, which `NWPathMonitor` delivers as
    /// soon as it starts. That update only reports the current state, so it is
    /// ignored (the app already refreshes at launch).
    static func connectionRestored(from previous: NWPath.Status?, to current: NWPath.Status) -> Bool {
        guard let previous else { return false }
        return previous != .satisfied && current == .satisfied
    }

    static let mainQueue: Scheduler = { delay, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}
