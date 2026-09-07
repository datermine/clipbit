import Foundation

/// The user's real home directory, even inside the App Sandbox, where `NSHomeDirectory()`
/// and `~` expansion point at the container instead.
enum HomeDirectory {
    static let real: String = {
        if let directory = getpwuid(getuid())?.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }()

    static func expandingTilde(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return real + path.dropFirst()
    }

    static func abbreviatingWithTilde(_ path: String) -> String {
        if path == real { return "~" }
        if path.hasPrefix(real + "/") { return "~" + path.dropFirst(real.count) }
        return path
    }
}
