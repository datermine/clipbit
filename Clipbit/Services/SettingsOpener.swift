import AppKit
import SwiftUI
import os

/// Opens the SwiftUI `Settings` scene from AppKit. If the (undocumented) responder-chain
/// action doesn't produce a window, hosts the same view in a plain window instead.
@MainActor
enum SettingsOpener {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clipbit", category: "settings")
    private static var fallbackWindow: NSWindow?

    static func open() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            // Activation is asynchronous on modern macOS and SwiftUI ignores the action while inactive.
            for _ in 0..<10 where !NSApp.isActive {
                try? await Task.sleep(for: .milliseconds(50))
            }

            let visibleBefore = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
            let sent = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                || NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            try? await Task.sleep(for: .milliseconds(200))

            let settingsWindow = NSApp.windows.first { window in
                guard window.isVisible, window !== fallbackWindow else { return false }
                let isNew = !visibleBefore.contains(ObjectIdentifier(window))
                let looksLikeSettings = window.title.localizedCaseInsensitiveContains("settings")
                    || (window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false)
                return looksLikeSettings || (isNew && window.styleMask.contains(.titled))
            }
            if let settingsWindow {
                settingsWindow.makeKeyAndOrderFront(nil)
                return
            }
            logger.info("SwiftUI Settings scene did not open (action sent: \(sent), app active: \(NSApp.isActive)); using fallback window")
            showFallbackWindow()
        }
    }

    private static func showFallbackWindow() {
        let window: NSWindow
        if let existing = fallbackWindow {
            window = existing
        } else {
            window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Clipbit Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            fallbackWindow = window
        }
        window.makeKeyAndOrderFront(nil)
    }
}
