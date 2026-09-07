#if DEBUG
import AppKit
import SwiftUI
import os

/// Development-only hooks, driven by environment variables (Debug builds only):
///
/// - `CLIPBIT_DEBUG_POPOVER=pinned|hover` — show the popover ~1.5 s after launch.
/// - `CLIPBIT_DEBUG_SNAPSHOTS=1` — render the preview card for every clipboard change to PNG
///   files under the app's temporary directory (paths are logged, subsystem = bundle id).
/// - `CLIPBIT_DEBUG_SETTINGS=1` — open the Settings window after launch and log what appeared.
enum DebugHooks {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clipbit", category: "debug")

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }
    static var popoverMode: String? { environment["CLIPBIT_DEBUG_POPOVER"] }
    static var snapshotsEnabled: Bool { environment["CLIPBIT_DEBUG_SNAPSHOTS"] != nil }
    static var openSettings: Bool { environment["CLIPBIT_DEBUG_SETTINGS"] != nil }

    @MainActor private static var currentModel: PreviewModel?

    /// Renders the card right away, then again 2 s later (after favicons/thumbnails arrive),
    /// and finally in its pinned form.
    @MainActor
    static func scheduleSnapshots(for state: ClipboardState) {
        guard snapshotsEnabled else { return }
        let model = PreviewModel()
        model.isVisible = true
        model.update(state: state, pinned: false)
        currentModel = model
        render(model, state: state, tag: "early")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard currentModel === model else { return }
            render(model, state: state, tag: "late")
            model.update(state: state, pinned: true)
            render(model, state: state, tag: "pinned")
        }
    }

    @MainActor
    private static func render(_ model: PreviewModel, state: ClipboardState, tag: String) {
        let hosting = NSHostingView(rootView: PreviewView(model: model))
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else { return }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipbit-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(state.changeCount)-\(state.kind.rawValue)-\(tag).png")
        do {
            try png.write(to: url)
            logger.info("snapshot \(url.path, privacy: .public) size=\(Int(size.width))x\(Int(size.height))")
        } catch {
            logger.error("snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    static func openSettingsAndReport() {
        SettingsOpener.open()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            let windows = NSApp.windows.filter(\.isVisible).map { window in
                "\(String(describing: type(of: window))) '\(window.title)' id=\(window.identifier?.rawValue ?? "-") \(Int(window.frame.width))x\(Int(window.frame.height))"
            }
            logger.info("visible windows after opening settings: \(windows.joined(separator: " | "), privacy: .public)")
        }
    }
}
#endif
