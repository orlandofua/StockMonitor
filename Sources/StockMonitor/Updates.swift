import AppKit
import Sparkle

/// The parts of Sparkle's updater that the menu uses, so tests can replace it
/// with a fake and never start a real updater.
protocol UpdaterBackend: AnyObject {
    /// False while a check is already running, for example.
    var canCheckForUpdates: Bool { get }
    /// Sparkle stores this in the app's user defaults (`SUAutomaticallyUpdate`),
    /// so it survives a relaunch without a key of our own.
    var automaticallyDownloadsUpdates: Bool { get set }
    /// False when the bundle or the user turned off the option to install automatically.
    var allowsAutomaticUpdates: Bool { get }
    /// A user-initiated check, with Sparkle's standard window ("up to date" or the update prompt).
    func checkForUpdates()
}

/// Sparkle's standard updater and user driver (ADR 0015).
final class SparkleUpdaterBackend: UpdaterBackend {
    private let controller: SPUStandardUpdaterController

    /// Starts the updater. Throws, instead of showing Sparkle's "contact the
    /// developer" alert, when the bundle is not set up for updates.
    init() throws {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        try controller.updater.start()
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }
    var allowsAutomaticUpdates: Bool { controller.updater.allowsAutomaticUpdates }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}

/// The "Check for Updates…" and "Install Updates Automatically" menu items
/// (issue #30, ADR 0015).
///
/// A build without an update feed (no `SUFeedURL` or no `SUPublicEDKey` in its
/// Info.plist, as with a plain `./build.sh`) never starts Sparkle, never checks
/// for updates, shows no alert, and gets no update menu items.
///
/// The background check once a day, and the default of asking before an install,
/// come from the Info.plist keys written by `scripts/make-info-plist.sh`.
final class Updates: NSObject, NSMenuItemValidation {
    static let checkTitle = "Check for Updates…"
    static let autoInstallTitle = "Install Updates Automatically"

    /// Info.plist keys that must both be present and non-empty for updates to run.
    static let feedURLKey = "SUFeedURL"
    static let publicKeyKey = "SUPublicEDKey"

    /// Nil when updates are off for this build.
    private let backend: UpdaterBackend?
    private let activateApp: () -> Void

    /// - Parameters:
    ///   - info: the bundle's Info.plist values.
    ///   - startBackend: starts the updater. Only called when `info` has a feed
    ///     URL and a public key. If it throws, updates stay off for this run.
    ///   - activateApp: brings the app to the front so Sparkle's window is not
    ///     hidden behind other apps (StockMonitor has no Dock icon).
    init(info: [String: Any]?,
         startBackend: () throws -> UpdaterBackend = { try SparkleUpdaterBackend() },
         activateApp: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) }) {
        var backend: UpdaterBackend?
        if Self.isConfigured(info) {
            do {
                backend = try startBackend()
            } catch {
                NSLog("StockMonitor: in-app updates are off, the updater did not start: %@", error.localizedDescription)
            }
        }
        self.backend = backend
        self.activateApp = activateApp
    }

    /// True when the Info.plist has both a feed URL and a public key.
    static func isConfigured(_ info: [String: Any]?) -> Bool {
        func nonEmpty(_ key: String) -> Bool {
            guard let value = info?[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return nonEmpty(feedURLKey) && nonEmpty(publicKeyKey)
    }

    /// False for a build with no update feed, or when the updater failed to start.
    var isAvailable: Bool { backend != nil }

    var canCheckForUpdates: Bool { backend?.canCheckForUpdates ?? false }

    var autoInstallState: NSControl.StateValue {
        guard let backend, backend.allowsAutomaticUpdates else { return .off }
        return backend.automaticallyDownloadsUpdates ? .on : .off
    }

    var canChangeAutoInstall: Bool { backend?.allowsAutomaticUpdates ?? false }

    /// The update items for a ticker menu, or none when updates are off.
    func menuItems() -> [NSMenuItem] {
        guard isAvailable else { return [] }
        let check = NSMenuItem(title: Self.checkTitle, action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        check.target = self
        let auto = NSMenuItem(title: Self.autoInstallTitle, action: #selector(toggleAutoInstall(_:)), keyEquivalent: "")
        auto.target = self
        auto.state = autoInstallState
        auto.toolTip = "Download updates in the background and install them when StockMonitor quits or relaunches."
        return [check, auto]
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard let backend, backend.canCheckForUpdates else { return }
        activateApp()
        backend.checkForUpdates()
    }

    @objc func toggleAutoInstall(_ sender: Any?) {
        guard let backend, backend.allowsAutomaticUpdates else { return }
        backend.automaticallyDownloadsUpdates.toggle()
    }

    /// Menus enable items automatically, so this keeps "Check for Updates…"
    /// greyed out while a check is running.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates(_:)): return canCheckForUpdates
        case #selector(toggleAutoInstall(_:)): return canChangeAutoInstall
        default: return true
        }
    }
}
