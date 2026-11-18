// Spike #28: a menu-bar-less stand-in for StockMonitor that starts a Sparkle 2 updater.
//
// It uses a small user driver that answers "install" to every prompt, so the whole
// find -> download -> verify -> install -> relaunch path runs without clicks.
// Every step is appended to the file named by the SpikeLogPath Info.plist key.
import AppKit
import Sparkle

let info = Bundle.main.infoDictionary ?? [:]
let version = info["CFBundleVersion"] as? String ?? "?"
let logPath = info["SpikeLogPath"] as? String ?? NSTemporaryDirectory() + "sparkle-spike.log"

func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) pid=\(getpid()) v=\(version) \(message)\n"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
}

final class AutoInstallDriver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        log("permission request -> allow")
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { log("check started") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        log("update found: version=\(appcastItem.versionString) short=\(appcastItem.displayVersionString) -> install")
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        log("no update: \(error.localizedDescription)")
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let ns = error as NSError
        log("UPDATER ERROR domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription) underlying=\(String(describing: ns.userInfo[NSUnderlyingErrorKey]))")
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { log("download started") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { log("download finished, extracting (EdDSA check happens here)") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        log("ready to install and relaunch -> install")
        reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        log("installing, applicationTerminated=\(applicationTerminated)")
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        log("installed and relaunched=\(relaunched)")
        acknowledgement()
    }
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() { log("dismiss update installation") }
}

final class Delegate: NSObject, NSApplicationDelegate {
    let driver = AutoInstallDriver()
    var updater: SPUUpdater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("launched path=\(Bundle.main.bundlePath) sparkle=\(Bundle(for: SPUUpdater.self).infoDictionary?["CFBundleShortVersionString"] ?? "?")")
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        do {
            try updater.start()
            log("updater started, feed=\(updater.feedURL?.absoluteString ?? "nil")")
        } catch {
            log("UPDATER START FAILED \(error)")
            return
        }
        self.updater = updater
        if info["SpikeCheckOnLaunch"] as? Bool == true {
            updater.checkForUpdates()
        }
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
