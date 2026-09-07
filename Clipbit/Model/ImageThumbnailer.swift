import AppKit
import ImageIO

/// Fast, decode-once thumbnail generation for image data on the pasteboard.
enum ImageThumbnailer {
    /// Long-edge pixel cap for the popover thumbnail (280×160 pt at 2×).
    static let popoverMaxPixels = 560
    /// Point size of the menu bar thumbnail used by "Thumbnail mode".
    static let menuBarPointSize: CGFloat = 16

    static func summary(data: Data, type: NSPasteboard.PasteboardType, format: String, fileExtension: String) -> ImageSummary? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        var pixelSize = pixelSize(of: source)
        let thumbnail = thumbnail(from: source, maxPixelSize: popoverMaxPixels)
        if pixelSize == .zero, let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            pixelSize = CGSize(width: image.width, height: image.height)
        }

        return ImageSummary(
            data: data,
            pasteboardType: type,
            format: format,
            fileExtension: fileExtension,
            pixelSize: pixelSize,
            thumbnail: thumbnail.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / 2, height: CGFloat($0.height) / 2)) },
            menuBarThumbnail: thumbnail.map(menuBarImage(from:))
        )
    }

    private static func pixelSize(of source: CGImageSource) -> CGSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return .zero }
        // EXIF orientations 5–8 are rotated 90°, so the displayed size is swapped.
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    private static func thumbnail(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A 16×16 pt, aspect-filled, 2 pt-rounded, non-template image for the status item.
    static func menuBarImage(from cgImage: CGImage) -> NSImage {
        let size = NSSize(width: menuBarPointSize, height: menuBarPointSize)
        let sourceImage = NSImage(cgImage: cgImage, size: .zero)
        let image = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).addClip()
            let sourceSize = sourceImage.size
            guard sourceSize.width > 0, sourceSize.height > 0 else { return false }
            let scale = max(rect.width / sourceSize.width, rect.height / sourceSize.height)
            let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let drawRect = NSRect(
                x: rect.midX - drawSize.width / 2,
                y: rect.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            sourceImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }
}
