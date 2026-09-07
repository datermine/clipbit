import Foundation

/// UserDefaults-backed settings. SwiftUI reads the same keys via `@AppStorage`.
enum Preferences {
    enum Key {
        static let pollInterval = "pollInterval"              // seconds: 0.25 / 0.5 / 1
        static let thumbnailMode = "thumbnailMode"            // Bool
        static let showSourceApp = "showSourceApp"            // Bool
        static let hoverDelay = "hoverDelayMilliseconds"      // 100 / 150 / 300
    }

    static let pollIntervalChoices: [TimeInterval] = [0.25, 0.5, 1.0]
    static let hoverDelayChoices: [Double] = [100, 150, 300]

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.pollInterval: 0.5,
            Key.thumbnailMode: false,
            Key.showSourceApp: true,
            Key.hoverDelay: 150.0,
        ])
    }

    static var pollInterval: TimeInterval {
        get { defaults.double(forKey: Key.pollInterval) }
        set { defaults.set(newValue, forKey: Key.pollInterval) }
    }

    static var thumbnailMode: Bool {
        get { defaults.bool(forKey: Key.thumbnailMode) }
        set { defaults.set(newValue, forKey: Key.thumbnailMode) }
    }

    static var showSourceApp: Bool {
        get { defaults.bool(forKey: Key.showSourceApp) }
        set { defaults.set(newValue, forKey: Key.showSourceApp) }
    }

    static var hoverDelayMilliseconds: Double {
        get { defaults.double(forKey: Key.hoverDelay) }
        set { defaults.set(newValue, forKey: Key.hoverDelay) }
    }
}
