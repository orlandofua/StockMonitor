import AppKit
import ServiceManagement
import Testing
@testable import StockMonitor

/// Stands in for `SMAppService.mainApp`, so tests never touch the real Login Items.
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status
    /// Status after a successful `register()`.
    var statusAfterRegister: SMAppService.Status = .enabled
    var error: Error?
    private(set) var calls: [String] = []

    init(status: SMAppService.Status) { self.status = status }

    func register() throws {
        calls.append("register")
        if let error { throw error }
        status = statusAfterRegister
    }

    func unregister() throws {
        calls.append("unregister")
        if let error { throw error }
        status = .notRegistered
    }
}

private struct FakeError: LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
}

@Suite("Launch at Login")
struct LaunchAtLoginTests {
    // MARK: Checkmark

    @Test(arguments: [
        (SMAppService.Status.enabled, NSControl.StateValue.on),
        (SMAppService.Status.notRegistered, NSControl.StateValue.off),
        (SMAppService.Status.notFound, NSControl.StateValue.off),
        (SMAppService.Status.requiresApproval, NSControl.StateValue.mixed),
    ])
    func checkmarkReflectsSystemStatus(status: SMAppService.Status, expected: NSControl.StateValue) {
        #expect(LaunchAtLogin.menuState(for: status) == expected)
    }

    @Test func checkmarkFollowsChangesMadeOutsideTheApp() {
        let service = FakeLoginItemService(status: .enabled)
        let toggle = LaunchAtLogin(service: service, openSystemSettings: {})
        #expect(toggle.menuState == .on)

        // The user removes the app in System Settings > General > Login Items.
        service.status = .notRegistered
        #expect(toggle.menuState == .off)

        // Or switches it off under "Allow in the Background".
        service.status = .requiresApproval
        #expect(toggle.menuState == .mixed)
        #expect(toggle.toolTip != nil)
    }

    @Test func onlyApprovalStateHasToolTip() {
        #expect(LaunchAtLogin.toolTip(for: .enabled) == nil)
        #expect(LaunchAtLogin.toolTip(for: .notRegistered) == nil)
        #expect(LaunchAtLogin.toolTip(for: .requiresApproval)?.contains("Login Items") == true)
    }

    // MARK: Toggle

    @Test func turningOnRegistersTheApp() throws {
        let service = FakeLoginItemService(status: .notRegistered)
        var opened = 0
        let toggle = LaunchAtLogin(service: service, openSystemSettings: { opened += 1 })

        #expect(try toggle.toggle() == .register)
        #expect(service.calls == ["register"])
        #expect(toggle.menuState == .on)
        #expect(opened == 0)
    }

    @Test func turningOffUnregistersTheApp() throws {
        let service = FakeLoginItemService(status: .enabled)
        let toggle = LaunchAtLogin(service: service, openSystemSettings: {})

        #expect(try toggle.toggle() == .unregister)
        #expect(service.calls == ["unregister"])
        #expect(toggle.menuState == .off)
    }

    @Test func notFoundTriesToRegister() throws {
        let service = FakeLoginItemService(status: .notFound)
        let toggle = LaunchAtLogin(service: service, openSystemSettings: {})
        #expect(try toggle.toggle() == .register)
    }

    @Test func registeringThatNeedsApprovalOpensSystemSettings() throws {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        var opened = 0
        let toggle = LaunchAtLogin(service: service, openSystemSettings: { opened += 1 })

        try toggle.toggle()
        #expect(opened == 1)
        #expect(toggle.menuState == .mixed)
    }

    @Test func clickingWhileWaitingForApprovalOpensSystemSettings() throws {
        let service = FakeLoginItemService(status: .requiresApproval)
        var opened = 0
        let toggle = LaunchAtLogin(service: service, openSystemSettings: { opened += 1 })

        #expect(try toggle.toggle() == .openSystemSettings)
        #expect(opened == 1)
        #expect(service.calls.isEmpty)
    }

    // MARK: Errors

    @Test func registerErrorIsReportedNotSwallowed() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.error = FakeError()
        let toggle = LaunchAtLogin(service: service, openSystemSettings: {})

        let failure = #expect(throws: LaunchAtLogin.Failure.self) { try toggle.toggle() }
        #expect(failure?.action == .register)
        #expect(failure?.message == "StockMonitor could not be added to Login Items.")
        #expect(failure?.informativeText.contains("Operation not permitted") == true)
        #expect(toggle.menuState == .off)
    }

    @Test(arguments: [SMAppService.Status.notRegistered, SMAppService.Status.notFound])
    func registerThatChangesNothingIsReported(statusAfter: SMAppService.Status) {
        // register() returns without an error, but the app is still not a login item.
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = statusAfter
        var opened = 0
        let toggle = LaunchAtLogin(service: service, openSystemSettings: { opened += 1 })

        let failure = #expect(throws: LaunchAtLogin.Failure.self) { try toggle.toggle() }
        #expect(failure?.action == .register)
        #expect(failure?.message == "StockMonitor could not be added to Login Items.")
        #expect(failure?.underlying is LaunchAtLogin.NotRegistered)
        #expect(toggle.menuState == .off)
        #expect(opened == 0)
    }

    @Test func notFoundAfterRegisterSuggestsApplicationsFolder() {
        let error = LaunchAtLogin.NotRegistered(status: .notFound)
        #expect(error.localizedDescription.contains("/Applications"))
    }

    @Test func unregisterErrorIsReportedNotSwallowed() {
        let service = FakeLoginItemService(status: .enabled)
        service.error = FakeError()
        let toggle = LaunchAtLogin(service: service, openSystemSettings: {})

        let failure = #expect(throws: LaunchAtLogin.Failure.self) { try toggle.toggle() }
        #expect(failure?.action == .unregister)
        #expect(failure?.message == "StockMonitor could not be removed from Login Items.")
        #expect(toggle.menuState == .on)
    }
}
