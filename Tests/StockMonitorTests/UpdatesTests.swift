import AppKit
import Testing
@testable import StockMonitor

/// Stands in for Sparkle's updater, so tests never start a real one or touch the network.
/// The auto-install flag lives in a UserDefaults suite under Sparkle's own key, the way
/// Sparkle persists it, so a "relaunch" can be simulated with a second fake on the same suite.
private final class FakeUpdaterBackend: UpdaterBackend {
    let defaults: UserDefaults
    var canCheckForUpdates = true
    var allowsAutomaticUpdates = true
    private(set) var checks = 0

    init(defaults: UserDefaults) { self.defaults = defaults }

    var automaticallyDownloadsUpdates: Bool {
        get { defaults.bool(forKey: "SUAutomaticallyUpdate") }
        set { defaults.set(newValue, forKey: "SUAutomaticallyUpdate") }
    }

    func checkForUpdates() { checks += 1 }
}

private struct StartFailed: Error {}

private let configured: [String: Any] = [
    "SUFeedURL": "https://orlandofua.github.io/StockMonitor/appcast.xml",
    "SUPublicEDKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
]

@Suite("In-app updates")
struct UpdatesTests {
    private func makeDefaults() -> UserDefaults {
        let name = "UpdatesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: No feed URL

    @Test(arguments: [
        nil,
        [:],
        ["SUFeedURL": "https://example.com/appcast.xml"],
        ["SUPublicEDKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="],
        ["SUFeedURL": "", "SUPublicEDKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="],
        ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "  "],
        ["SUFeedURL": 42, "SUPublicEDKey": true],
    ] as [[String: Any]?])
    func buildWithoutFeedNeverStartsTheUpdater(info: [String: Any]?) {
        var started = false
        var activated = false
        let updates = Updates(info: info, startBackend: {
            started = true
            return FakeUpdaterBackend(defaults: makeDefaults())
        }, activateApp: { activated = true })

        #expect(!started)
        #expect(!updates.isAvailable)
        #expect(updates.menuItems().isEmpty)
        #expect(!updates.canCheckForUpdates)
        #expect(updates.autoInstallState == .off)

        // Even if an action were sent somehow, nothing happens and nothing is shown.
        updates.checkForUpdates(nil)
        updates.toggleAutoInstall(nil)
        #expect(!activated)
    }

    @Test func updaterThatFailsToStartLeavesUpdatesOffWithoutThrowing() {
        let updates = Updates(info: configured, startBackend: { throw StartFailed() }, activateApp: {})
        #expect(!updates.isAvailable)
        #expect(updates.menuItems().isEmpty)
    }

    @Test(arguments: [
        ([:], false),
        (["SUFeedURL": "https://example.com/appcast.xml"], false),
        (["SUPublicEDKey": "key"], false),
        (["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "key"], true),
    ] as [([String: Any], Bool)])
    func configurationNeedsFeedAndKey(info: [String: Any], expected: Bool) {
        #expect(Updates.isConfigured(info) == expected)
    }

    // MARK: Menu state

    @Test func configuredBuildStartsTheUpdaterAndShowsBothItems() {
        var started = 0
        let updates = Updates(info: configured, startBackend: {
            started += 1
            return FakeUpdaterBackend(defaults: makeDefaults())
        }, activateApp: {})

        #expect(started == 1)
        #expect(updates.isAvailable)
        let items = updates.menuItems()
        #expect(items.map(\.title) == [Updates.checkTitle, Updates.autoInstallTitle])
        #expect(items.allSatisfy { $0.target === updates })
    }

    @Test func checkForUpdatesBringsTheAppForwardAndAsksSparkle() {
        let backend = FakeUpdaterBackend(defaults: makeDefaults())
        var activated = 0
        let updates = Updates(info: configured, startBackend: { backend }, activateApp: { activated += 1 })

        updates.menuItems()[0].performAction()
        #expect(backend.checks == 1)
        #expect(activated == 1)
    }

    @Test func checkIsDisabledWhileSparkleCannotCheck() {
        let backend = FakeUpdaterBackend(defaults: makeDefaults())
        let updates = Updates(info: configured, startBackend: { backend }, activateApp: {})
        let check = updates.menuItems()[0]
        #expect(updates.validateMenuItem(check))

        backend.canCheckForUpdates = false // a check is already running
        #expect(!updates.validateMenuItem(check))
        updates.checkForUpdates(nil)
        #expect(backend.checks == 0)
    }

    // MARK: Install automatically

    @Test func autoInstallIsOffByDefaultSoUpdatesArePrompted() {
        let updates = Updates(info: configured, startBackend: { FakeUpdaterBackend(defaults: makeDefaults()) },
                              activateApp: {})
        #expect(updates.autoInstallState == .off)
        #expect(updates.menuItems()[1].state == .off)
    }

    @Test func toggleFlipsAutoInstallAndShowsTheCheckmark() {
        let backend = FakeUpdaterBackend(defaults: makeDefaults())
        let updates = Updates(info: configured, startBackend: { backend }, activateApp: {})

        updates.menuItems()[1].performAction()
        #expect(backend.automaticallyDownloadsUpdates)
        #expect(updates.menuItems()[1].state == .on)

        updates.menuItems()[1].performAction()
        #expect(!backend.automaticallyDownloadsUpdates)
        #expect(updates.menuItems()[1].state == .off)
    }

    @Test func autoInstallKeepsItsValueAfterARelaunch() {
        let defaults = makeDefaults()
        let first = Updates(info: configured, startBackend: { FakeUpdaterBackend(defaults: defaults) }, activateApp: {})
        first.toggleAutoInstall(nil)
        #expect(first.autoInstallState == .on)

        // A new launch reads the same user defaults.
        let relaunched = Updates(info: configured, startBackend: { FakeUpdaterBackend(defaults: defaults) },
                                 activateApp: {})
        #expect(relaunched.autoInstallState == .on)
    }

    @Test func toggleIsDisabledWhenAutomaticUpdatesAreNotAllowed() {
        let backend = FakeUpdaterBackend(defaults: makeDefaults())
        backend.allowsAutomaticUpdates = false
        backend.automaticallyDownloadsUpdates = true
        let updates = Updates(info: configured, startBackend: { backend }, activateApp: {})

        let toggle = updates.menuItems()[1]
        #expect(!updates.validateMenuItem(toggle))
        // Sparkle ignores the stored value in this case, so no checkmark either.
        #expect(toggle.state == .off)
        updates.toggleAutoInstall(nil)
        #expect(backend.automaticallyDownloadsUpdates)
    }
}

private extension NSMenuItem {
    /// Sends the item's action to its target, as a click would.
    func performAction() {
        guard let action, let target = target as? NSObject else { return }
        target.perform(action, with: self)
    }
}
