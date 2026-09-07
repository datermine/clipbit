import SwiftUI

@main
struct ClipbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The only SwiftUI scene: a tiny Settings window, reachable from the status item menu.
        Settings {
            SettingsView()
        }
    }
}
