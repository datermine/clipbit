import AppKit

/// SF Symbol template images for each clipboard kind (SPEC §3).
enum StatusIcon {
    static func symbolName(for state: ClipboardState) -> String {
        switch state.content {
        case .empty: return "clipboard"
        case .text: return "doc.text"
        case .url: return "link"
        case .image: return "photo"
        case .file(let file): return file.isDirectory ? "folder" : "doc"
        case .other: return "questionmark.square.dashed"
        case .concealed: return "lock"
        }
    }

    static func accessibilityDescription(for state: ClipboardState) -> String {
        switch state.kind {
        case .empty: return "Clipboard is empty"
        case .text: return "Clipboard contains text"
        case .url: return "Clipboard contains a link"
        case .image: return "Clipboard contains an image"
        case .file: return "Clipboard contains a file"
        case .other: return "Clipboard contains other data"
        case .concealed: return "Clipboard content is concealed"
        }
    }

    static func image(for state: ClipboardState) -> NSImage? {
        let description = accessibilityDescription(for: state)
        let candidates = [symbolName(for: state), "doc.on.clipboard", "square.dashed"]
        for name in candidates {
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: description) else { continue }
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let image = symbol.withSymbolConfiguration(configuration) ?? symbol
            image.isTemplate = true
            return image
        }
        return nil
    }
}
