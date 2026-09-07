import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: ClipboardMonitor?
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        // LSUIElement in Info.plist already hides the Dock icon; this keeps behaviour
        // consistent when the binary is launched outside its bundle during development.
        NSApp.setActivationPolicy(.accessory)

        let monitor = ClipboardMonitor(interval: .seconds(Preferences.pollInterval))
        let controller = StatusItemController(monitor: monitor, router: ActionRouter())
        controller.start()
        self.monitor = monitor
        self.statusController = controller

        #if DEBUG
        installDebugHooks()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        let monitor = self.monitor
        Task { await monitor?.stop() }
    }

    #if DEBUG
    private func installDebugHooks() {
        let controller = statusController
        if let mode = DebugHooks.popoverMode {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                controller?.debugShowPopover(pinned: mode == "pinned")
            }
        }
        if DebugHooks.openSettings {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                DebugHooks.openSettingsAndReport()
            }
        }
    }
    #endif
}
