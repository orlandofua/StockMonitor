import AppKit
import ServiceManagement

/// The parts of `SMAppService` that the Launch at Login toggle uses, so tests
/// can replace the system service with a fake.
protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// The "Launch at Login" menu toggle (issue #10, ADR 0012).
///
/// The system is the source of truth: the checkmark is read from `status` every
/// time a menu opens, so changes made in System Settings show up too. Nothing
/// is stored in UserDefaults.
final class LaunchAtLogin {
    /// What a click on the menu item does for a given status.
    enum Action: Equatable {
        case register
        case unregister
        /// The item is registered but the user has to allow it in
        /// System Settings > General > Login Items.
        case openSystemSettings
    }

    /// A failed `register()` or `unregister()`, ready to show in an alert.
    struct Failure: Error {
        let action: Action
        let underlying: Error

        var message: String {
            action == .unregister
                ? "StockMonitor could not be removed from Login Items."
                : "StockMonitor could not be added to Login Items."
        }

        var informativeText: String {
            "\(underlying.localizedDescription)\n\nYou can change this in System Settings > General > Login Items."
        }
    }

    static let title = "Launch at Login"

    private let service: LoginItemService
    private let openSystemSettings: () -> Void

    init(service: LoginItemService = SMAppService.mainApp,
         openSystemSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }) {
        self.service = service
        self.openSystemSettings = openSystemSettings
    }

    /// Checkmark for the menu item: on when enabled, mixed when it waits for approval.
    static func menuState(for status: SMAppService.Status) -> NSControl.StateValue {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .mixed
        default: return .off
        }
    }

    /// Tooltip that explains a state the checkmark alone does not.
    static func toolTip(for status: SMAppService.Status) -> String? {
        status == .requiresApproval
            ? "Waiting for approval in System Settings > General > Login Items. Click to open it."
            : nil
    }

    static func action(for status: SMAppService.Status) -> Action {
        switch status {
        case .enabled: return .unregister
        case .requiresApproval: return .openSystemSettings
        default: return .register
        }
    }

    var menuState: NSControl.StateValue { Self.menuState(for: service.status) }
    var toolTip: String? { Self.toolTip(for: service.status) }

    /// Flips the setting. Throws a `Failure` when the system refuses.
    ///
    /// If registering leaves the item waiting for approval, System Settings is
    /// opened so the user can allow it right away.
    @discardableResult
    func toggle() throws -> Action {
        let action = Self.action(for: service.status)
        do {
            switch action {
            case .register:
                try service.register()
                if service.status == .requiresApproval { openSystemSettings() }
            case .unregister:
                try service.unregister()
            case .openSystemSettings:
                openSystemSettings()
            }
        } catch {
            throw Failure(action: action, underlying: error)
        }
        return action
    }
}
