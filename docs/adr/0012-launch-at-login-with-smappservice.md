# 12. Launch at login with SMAppService

Date: 2026-11-18

## Status

Accepted

## Context

The README told users to add StockMonitor to System Settings › General › Login Items by hand (issue #10). The app supports macOS 13 or later (ADR 0002), where `SMAppService.mainApp` from the ServiceManagement framework can register the app itself as a login item. The older options, `SMLoginItemSetEnabled` with a helper app or a LaunchAgent plist, need extra bundles or files that `build.sh` does not produce.

The user can also add, remove, or block the login item in System Settings at any time, so a copy of the setting kept by the app could go out of date.

## Decision

- Add a "Launch at Login" item to every ticker menu, next to the other settings. Clicking it calls `SMAppService.mainApp.register()` or `unregister()`.
- Treat macOS as the only source of truth. The checkmark is read from `SMAppService.mainApp.status` each time a menu opens, and nothing is stored in UserDefaults (ADR 0007 is unchanged).
- Map the statuses as follows: `enabled` shows a checkmark and clicking unregisters; `notRegistered` and `notFound` show no checkmark and clicking registers; `requiresApproval` shows a mixed state (dash), and clicking opens System Settings › Login Items with `SMAppService.openSystemSettingsLoginItems()`. If `register()` succeeds but leaves the item waiting for approval, Login Items opens right away.
- Show an alert when `register()` or `unregister()` throws, with the system's error text.
- Keep the logic in `LaunchAtLogin`, which talks to a small `LoginItemService` protocol that `SMAppService` conforms to, so unit tests use a fake and never change the real login items.

## Consequences

- No helper bundle, entitlements, or `build.sh` changes are needed.
- The login item points at the app bundle it was registered from. Users should move the app to `/Applications` first, and turn the setting off and on again if they move it later.
- The app is ad hoc signed (ADR 0010). macOS may show a "Background Items Added" notification, and some versions may need approval in Login Items. Whether registration works for an ad hoc signed app outside `/Applications` is checked by manual testing, not unit tests.
