import AppKit
import QuickLookThumbnailing

/// QuickLook thumbnails for image files on the pasteboard, keyed by URL.
actor FileThumbnailCache {
    static let shared = FileThumbnailCache()

    static let thumbnailSize = CGSize(width: 280, height: 160)
    private let capacity = 24

    private var images: [URL: NSImage] = [:]
    private var order: [URL] = []
    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    func thumbnail(for url: URL) async -> NSImage? {
        if let image = images[url] { return image }
        if let task = inflight[url] { return await task.value }

        let task = Task<NSImage?, Never> {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: FileThumbnailCache.thumbnailSize,
                scale: 2,
                representationTypes: .thumbnail
            )
            guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
                return nil
            }
            return representation.nsImage
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil

        if let image { store(image, for: url) }
        return image
    }

    private func store(_ image: NSImage, for url: URL) {
        if images[url] == nil {
            order.append(url)
            if order.count > capacity {
                let evicted = order.removeFirst()
                images[evicted] = nil
            }
        }
        images[url] = image
    }
}
