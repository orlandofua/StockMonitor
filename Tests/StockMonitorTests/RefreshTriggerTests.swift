import Foundation
import Network
import Testing
@testable import StockMonitor

/// A scheduler that records work instead of running it, so tests control time.
private final class ManualScheduler {
    struct Job { let delay: TimeInterval; let work: () -> Void; var cancelled = false }
    private(set) var jobs: [Job] = []

    var scheduler: RefreshTrigger.Scheduler {
        { [unowned self] delay, work in
            jobs.append(Job(delay: delay, work: work))
            let index = jobs.count - 1
            return { [unowned self] in jobs[index].cancelled = true }
        }
    }

    /// Runs every job that has not run or been cancelled.
    func runAll() {
        for i in jobs.indices where !jobs[i].cancelled {
            jobs[i].cancelled = true
            jobs[i].work()
        }
    }
}

@Suite("RefreshTrigger")
struct RefreshTriggerTests {
    @Test func firesOnceAfterTheDelay() {
        let clock = ManualScheduler()
        var refreshes = 0
        let trigger = RefreshTrigger(delay: 2, schedule: clock.scheduler) { refreshes += 1 }

        trigger.fire()
        #expect(refreshes == 0)
        #expect(clock.jobs.map(\.delay) == [2])

        clock.runAll()
        #expect(refreshes == 1)
        #expect(!trigger.isPending)
    }

    @Test func burstOfEventsCausesOneRefresh() {
        let clock = ManualScheduler()
        var refreshes = 0
        let trigger = RefreshTrigger(schedule: clock.scheduler) { refreshes += 1 }

        // Wake, then several network flaps before the delay passes.
        for _ in 0..<5 { trigger.fire() }
        #expect(clock.jobs.count == 1)

        clock.runAll()
        #expect(refreshes == 1)
    }

    @Test func eventAfterARefreshSchedulesAnotherOne() {
        let clock = ManualScheduler()
        var refreshes = 0
        let trigger = RefreshTrigger(schedule: clock.scheduler) { refreshes += 1 }

        trigger.fire()
        clock.runAll()
        trigger.fire()
        clock.runAll()
        #expect(refreshes == 2)
    }

    @Test func releaseCancelsScheduledJob() {
        var cancelled = false
        var trigger: RefreshTrigger? = RefreshTrigger(schedule: { _, _ in { cancelled = true } }) {}
        trigger?.fire()
        trigger = nil
        #expect(cancelled)
    }

    @Test(arguments: [
        (nil, NWPath.Status.satisfied, false),                    // first update at start
        (nil, NWPath.Status.unsatisfied, false),
        (NWPath.Status.unsatisfied, NWPath.Status.satisfied, true),   // Wi-Fi back on
        (NWPath.Status.requiresConnection, NWPath.Status.satisfied, true),
        (NWPath.Status.satisfied, NWPath.Status.satisfied, false),    // interface change, still online
        (NWPath.Status.satisfied, NWPath.Status.unsatisfied, false),  // going offline
        (NWPath.Status.unsatisfied, NWPath.Status.unsatisfied, false),
    ] as [(NWPath.Status?, NWPath.Status, Bool)])
    func connectionRestored(_ previous: NWPath.Status?, _ current: NWPath.Status, _ expected: Bool) {
        #expect(RefreshTrigger.connectionRestored(from: previous, to: current) == expected)
    }
}
