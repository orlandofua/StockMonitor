# 2. Native AppKit app built with Swift Package Manager

Date: 2026-11-17

## Status

Accepted. The signing consequence is superseded by [0017](0017-developer-id-signing-and-notarization.md).

## Context

StockMonitor is a menu-bar-only macOS utility. It must start quickly, use very little memory, and stay running all day. The development machine has the Xcode Command Line Tools but not full Xcode.

Options considered:

- **SwiftUI `MenuBarExtra`**: concise, but its label only supports plain text and images, with little control over layout. It also offers no easy way to show one menu bar item per symbol.
- **Electron or another web-based shell**: much larger memory and disk footprint than a menu bar ticker warrants.
- **AppKit `NSStatusItem`**: full control over each item's button, image, and menu.
- **Xcode project vs. Swift Package Manager**: an Xcode project needs full Xcode to build; a Swift package builds with `swift build` alone.

## Decision

- Write the app in Swift using AppKit (`NSStatusBar` / `NSStatusItem` / `NSMenu`).
- Build with Swift Package Manager as a single executable target (`Package.swift`, tools version 5.10, macOS 13+).
- Wrap the binary into `StockMonitor.app` with `build.sh`, which writes a minimal `Info.plist` with `LSUIElement = true` (no Dock icon) and applies an ad hoc code signature.
- Set the activation policy to `.accessory` in `main.swift`.

## Consequences

- No Xcode required; `./build.sh` is the whole build.
- The app has no asset catalog, app icon, or entitlements file. Adding these later means extending `build.sh` or moving to an Xcode project.
- The ad hoc signature is fine for local use. Distributing the app to other machines would need a Developer ID signature and notarization. (Done for releases in 0017.)
- Swift 5 language mode avoids strict concurrency checking. Moving to Swift 6 mode will need `@MainActor` annotations on the app delegate and the stream client.
