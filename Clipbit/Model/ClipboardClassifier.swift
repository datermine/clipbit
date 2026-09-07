import AppKit
import UniformTypeIdentifiers
import os

/// Turns the first pasteboard item into a `ClipboardState`. Pure functions, safe to call off-main.
enum ClipboardClassifier {
    /// Only this many bytes from the head and tail of a string are read for the preview.
    static let textReadCap = 10 * 1024
    /// Paths and URLs are short; strings longer than this skip the path/URL checks.
    private static let shortTextLimit = 4096

    private static let concealedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
    ]
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")

    private struct ImageFlavor {
        let type: NSPasteboard.PasteboardType
        let format: String
        let fileExtension: String
    }

    /// Preferred order: PNG is compact and lossless; TIFF last because it's usually the largest.
    private static let imageFlavors: [ImageFlavor] = [
        ImageFlavor(type: .png, format: "PNG", fileExtension: "png"),
        ImageFlavor(type: NSPasteboard.PasteboardType("public.jpeg"), format: "JPEG", fileExtension: "jpg"),
        ImageFlavor(type: NSPasteboard.PasteboardType("public.heic"), format: "HEIC", fileExtension: "heic"),
        ImageFlavor(type: .tiff, format: "TIFF", fileExtension: "tiff"),
    ]

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clipbit", category: "classifier")

    static func classify(pasteboard: NSPasteboard, changeCount: Int, frontmostApp: SourceApp?) -> ClipboardState {
        let items = pasteboard.pasteboardItems ?? []
        guard let first = items.first else {
            logger.info("changeCount=\(changeCount) kind=empty")
            return ClipboardState(changeCount: changeCount, content: .empty, itemCount: 0, sourceApp: nil)
        }

        let types = first.types
        let typeIDs = Set(types.map(\.rawValue))
        let source = declaredSource(in: first) ?? frontmostApp

        func state(_ content: ClipboardContent) -> ClipboardState {
            logger.info("changeCount=\(changeCount) kind=\(content.kind.rawValue, privacy: .public) items=\(items.count)")
            return ClipboardState(changeCount: changeCount, content: content, itemCount: items.count, sourceApp: source)
        }

        // 0. Concealed / transient (password managers). Never read anything else.
        if !typeIDs.isDisjoint(with: concealedTypes) {
            return state(.concealed)
        }

        // 1. File URLs.
        if types.contains(.fileURL) {
            let urls = items.compactMap(fileURL(from:))
            if let summary = fileSummary(for: urls) {
                return state(.file(summary))
            }
        }

        // Read the plain-text bytes once; several rules below need them.
        let stringData: Data? = types.contains(.string) ? first.data(forType: .string) : nil
        let shortText: String? = stringData.flatMap { $0.count <= shortTextLimit ? String(data: $0, encoding: .utf8) : nil }

        // 1b. Plain text that is an absolute path to something that exists (e.g. copied from Terminal).
        if let text = shortText, let url = existingPathURL(in: text), let summary = fileSummary(for: [url]) {
            return state(.file(summary))
        }

        // 2. Image data.
        for flavor in imageFlavors where types.contains(flavor.type) {
            if let data = first.data(forType: flavor.type),
               let summary = ImageThumbnailer.summary(data: data, type: flavor.type, format: flavor.format, fileExtension: flavor.fileExtension) {
                return state(.image(summary))
            }
        }

        // 3. URL.
        if types.contains(.URL), let raw = first.string(forType: .URL), let summary = urlSummary(from: raw) {
            return state(.url(summary))
        }
        if let text = shortText, let summary = urlSummary(from: text) {
            return state(.url(summary))
        }

        // 4. Text. Always prefer the plain-string representation; fall back to converting RTF.
        if let data = stringData {
            return state(.text(textSummary(utf8: data)))
        }
        if types.contains(.rtf), let data = first.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            return state(.text(textSummary(string: attributed.string, isTruncated: false)))
        }

        // 5. Something we don't understand (custom app types).
        return state(.other(OtherSummary(types: types.map(\.rawValue))))
    }

    // MARK: - Source app

    private static func declaredSource(in item: NSPasteboardItem) -> SourceApp? {
        guard item.types.contains(sourceType),
              let bundleID = item.string(forType: sourceType)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty
        else { return nil }
        return SourceApp.lookup(bundleIdentifier: bundleID)
    }

    // MARK: - Files

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        guard let raw = item.string(forType: .fileURL), let url = URL(string: raw), url.isFileURL else { return nil }
        // Finder often writes file-reference URLs (file:///.file/id=…); resolve to a path URL.
        return (url as NSURL).filePathURL ?? url
    }

    private static func existingPathURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 1024, !trimmed.contains(where: \.isNewline) else { return nil }

        var candidates: [String] = []
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = HomeDirectory.expandingTilde(in: trimmed)
            candidates.append(expanded)
            if expanded.contains("\\ ") {
                // Terminal-escaped spaces: "/Users/me/My\ File.txt"
                candidates.append(expanded.replacingOccurrences(of: "\\ ", with: " "))
            }
        } else if trimmed.lowercased().hasPrefix("file://"), let url = URL(string: trimmed), url.isFileURL {
            candidates.append(url.path)
        } else {
            return nil
        }

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func fileSummary(for urls: [URL]) -> FileSummary? {
        guard let primary = urls.first else { return nil }
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: primary.path, isDirectory: &isDirectory)

        let contentType = (try? primary.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: primary.pathExtension)
        let isImage = !isDirectory.boolValue && (contentType?.conforms(to: .image) ?? false)
        return FileSummary(urls: urls, isDirectory: isDirectory.boolValue, isImage: isImage)
    }

    // MARK: - URLs

    private static func urlSummary(from text: String) -> URLSummary? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 8192,
              !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased()
        else { return nil }

        switch scheme {
        case "http", "https", "file":
            // URLComponents keeps a trailing slash and decodes percent-escapes for display.
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let host = components?.host ?? url.host, !host.isEmpty else { return nil }
            var subtitle = components?.path ?? url.path
            if subtitle.isEmpty { subtitle = "/" }
            if let query = components?.query, !query.isEmpty { subtitle += "?" + query }
            if let fragment = components?.fragment, !fragment.isEmpty { subtitle += "#" + fragment }
            return URLSummary(url: url, title: host, subtitle: subtitle)
        case "mailto":
            let address = url.path.isEmpty ? String(trimmed.dropFirst("mailto:".count)) : url.path
            guard address.contains("@") else { return nil }
            return URLSummary(url: url, title: address, subtitle: "Email address")
        default:
            return nil
        }
    }

    // MARK: - Text

    static func textSummary(utf8 data: Data) -> TextSummary {
        let cap = textReadCap
        guard data.count > 2 * cap else {
            return textSummary(string: String(decoding: data, as: UTF8.self), isTruncated: false)
        }

        // Huge text: decode only the head and tail, dropping any replacement character
        // produced by cutting a multi-byte sequence.
        var head = String(decoding: data.prefix(cap), as: UTF8.self)
        while head.last == "\u{FFFD}" { head.removeLast() }
        var tail = String(decoding: data.suffix(cap), as: UTF8.self)
        while tail.first == "\u{FFFD}" { tail.removeFirst() }

        let preview = String(collapse(head).prefix(16)) + " … " + String(collapse(tail).suffix(16))
        let full = head + "\n\n⋯ [only the first and last 10 KB were read] ⋯\n\n" + tail
        return TextSummary(
            preview: preview,
            fullText: full,
            characterCount: head.count + tail.count,
            lineCount: lineCount(of: head) + lineCount(of: tail),
            isTruncated: true
        )
    }

    static func textSummary(string: String, isTruncated: Bool) -> TextSummary {
        let collapsed = collapse(string)
        let preview: String
        if collapsed.count <= 32 {
            preview = collapsed
        } else {
            preview = String(collapsed.prefix(16)) + " … " + String(collapsed.suffix(16))
        }
        return TextSummary(
            preview: preview,
            fullText: string,
            characterCount: string.count,
            lineCount: lineCount(of: string),
            isTruncated: isTruncated
        )
    }

    /// Collapse whitespace runs to a single space and render newlines as ⏎.
    static func collapse(_ string: String) -> String {
        var output = ""
        output.reserveCapacity(min(string.utf8.count, 512))
        var pendingSpace = false
        for character in string {
            if character.isNewline {
                output.append("⏎")
                pendingSpace = false
            } else if character.isWhitespace {
                pendingSpace = true
            } else {
                if pendingSpace, !output.isEmpty { output.append(" ") }
                pendingSpace = false
                output.append(character)
            }
        }
        return output
    }

    /// Counts lines the way `wc -l` users expect: a trailing newline doesn't add an empty line.
    static func lineCount(of string: String) -> Int {
        guard !string.isEmpty else { return 0 }
        var count = 0
        var endsWithNewline = false
        for character in string {
            endsWithNewline = character.isNewline
            if endsWithNewline { count += 1 }
        }
        return endsWithNewline ? count : count + 1
    }
}
