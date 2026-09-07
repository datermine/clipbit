import AppKit

/// Broad category of what is on the pasteboard. See SPEC §2 for the classification order.
enum ClipboardKind: String, Sendable {
    case concealed, file, image, url, text, other, empty
}

/// Best-effort identification of the app that put the current item on the pasteboard.
struct SourceApp: @unchecked Sendable {
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?

    /// The frontmost application right now, unless it's Clipbit itself.
    @MainActor
    static func frontmost() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.bundleIdentifier != "com.apple.loginwindow",
              let name = app.localizedName
        else { return nil }
        return SourceApp(name: name, bundleIdentifier: app.bundleIdentifier, icon: app.icon)
    }

    /// Resolve an app declared via the `org.nspasteboard.source` convention.
    static func lookup(bundleIdentifier: String) -> SourceApp? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           let name = app.localizedName {
            return SourceApp(name: name, bundleIdentifier: bundleIdentifier, icon: app.icon)
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return SourceApp(name: name, bundleIdentifier: bundleIdentifier, icon: NSWorkspace.shared.icon(forFile: url.path))
    }
}

struct TextSummary: Sendable {
    /// One-line preview: `first16 … last16` with whitespace collapsed and newlines shown as ⏎.
    let preview: String
    /// Text for the pinned view. Head + tail when the pasteboard string exceeded the read cap.
    let fullText: String
    let characterCount: Int
    let lineCount: Int
    /// True when only the first and last `ClipboardClassifier.textReadCap` bytes were read;
    /// counts are then lower bounds.
    let isTruncated: Bool
}

struct URLSummary: Sendable {
    let url: URL
    /// Bold line: host for web URLs, address for mailto.
    let title: String
    /// Secondary line: path + query for web URLs.
    let subtitle: String

    var isMail: Bool { url.scheme?.lowercased() == "mailto" }
}

struct FileSummary: Sendable {
    /// All file URLs on the pasteboard, first item first. Never empty.
    let urls: [URL]
    let isDirectory: Bool
    /// The first item's type conforms to `public.image`.
    let isImage: Bool

    var primary: URL { urls[0] }
    var count: Int { urls.count }
    var name: String { primary.lastPathComponent }
    var abbreviatedParent: String {
        HomeDirectory.abbreviatingWithTilde(primary.deletingLastPathComponent().path)
    }
}

struct ImageSummary: @unchecked Sendable {
    /// Raw pasteboard bytes in `pasteboardType`.
    let data: Data
    let pasteboardType: NSPasteboard.PasteboardType
    /// Display label: PNG / TIFF / JPEG / HEIC.
    let format: String
    let fileExtension: String
    let pixelSize: CGSize
    /// Fits within 560 px on the long edge; used by the popover.
    let thumbnail: NSImage?
    /// 16×16 pt rounded thumbnail for "Thumbnail mode" in the menu bar.
    let menuBarThumbnail: NSImage?
}

struct OtherSummary: Sendable {
    let types: [String]
}

enum ClipboardContent: @unchecked Sendable {
    case empty
    case concealed
    case text(TextSummary)
    case url(URLSummary)
    case image(ImageSummary)
    case file(FileSummary)
    case other(OtherSummary)

    var kind: ClipboardKind {
        switch self {
        case .empty: return .empty
        case .concealed: return .concealed
        case .text: return .text
        case .url: return .url
        case .image: return .image
        case .file: return .file
        case .other: return .other
        }
    }
}

/// Immutable snapshot of the pasteboard, published by `ClipboardMonitor`.
struct ClipboardState: @unchecked Sendable {
    let changeCount: Int
    let content: ClipboardContent
    /// Number of pasteboard items (e.g. 12 files copied in Finder). Classification uses the first.
    let itemCount: Int
    let sourceApp: SourceApp?

    var kind: ClipboardKind { content.kind }

    static let initial = ClipboardState(changeCount: -1, content: .empty, itemCount: 0, sourceApp: nil)
}
