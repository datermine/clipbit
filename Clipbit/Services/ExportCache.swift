import AppKit

/// `~/Library/Caches/<bundle id>/` — where images and text are written before handing
/// them to Preview or the default text editor. Kept to the last few files.
struct ExportCache: Sendable {
    static let keepCount = 5

    let directory: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Clipbit", isDirectory: true)
    }

    func write(_ data: Data, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Delete everything but the newest `keepCount` files.
    func prune(keeping keepCount: Int = ExportCache.keepCount) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let dated = files.map { url -> (URL, Date) in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (url, date)
        }
        for (url, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(keepCount) {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Bytes and extension to write for an image: PNG unless the source is already JPEG/HEIC.
    static func exportRepresentation(of image: ImageSummary) -> (data: Data, fileExtension: String) {
        switch image.format {
        case "PNG", "JPEG", "HEIC":
            return (image.data, image.fileExtension)
        default:
            if let bitmap = NSBitmapImageRep(data: image.data),
               let png = bitmap.representation(using: .png, properties: [:]) {
                return (png, "png")
            }
            return (image.data, image.fileExtension)
        }
    }
}
