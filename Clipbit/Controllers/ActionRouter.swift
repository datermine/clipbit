import AppKit

/// Performs the type-appropriate click action for a clipboard state (SPEC §5).
@MainActor
final class ActionRouter {
    enum Outcome {
        case none
        /// The caller should show the popover pinned with the full content.
        case showPinnedPreview
    }

    private let exportCache = ExportCache()
    private let pasteboard = NSPasteboard.general

    func perform(for state: ClipboardState, modifiers: NSEvent.ModifierFlags) -> Outcome {
        let option = modifiers.contains(.option)

        switch state.content {
        case .empty, .concealed:
            return .none

        case .file(let file):
            if option {
                for url in file.urls { NSWorkspace.shared.open(url) }
            } else {
                NSWorkspace.shared.activateFileViewerSelecting(file.urls)
            }
            return .none

        case .url(let url):
            NSWorkspace.shared.open(url.url)
            return .none

        case .image(let image):
            openInPreview(image, changeCount: state.changeCount)
            return .none

        case .text(let text):
            if option {
                openInTextEditor(text, changeCount: state.changeCount)
                return .none
            }
            return .showPinnedPreview

        case .other:
            return .showPinnedPreview
        }
    }

    // MARK: - Image → Preview

    private func openInPreview(_ image: ImageSummary, changeCount: Int) {
        let cache = exportCache
        Task.detached(priority: .userInitiated) {
            let representation = ExportCache.exportRepresentation(of: image)
            guard let url = try? cache.write(representation.data, name: "clip-\(changeCount).\(representation.fileExtension)") else { return }
            cache.prune()
            await MainActor.run {
                ActionRouter.open(url, preferringApplication: "com.apple.Preview")
            }
        }
    }

    private static func open(_ url: URL, preferringApplication bundleIdentifier: String) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        }
    }

    // MARK: - Text → default editor

    private func openInTextEditor(_ text: TextSummary, changeCount: Int) {
        // The summary may hold only head + tail of a huge string; the user asked for the
        // whole thing, so re-read it as long as the pasteboard hasn't moved on.
        let full: String
        if pasteboard.changeCount == changeCount, let current = pasteboard.string(forType: .string) {
            full = current
        } else {
            full = text.fullText
        }
        let cache = exportCache
        Task.detached(priority: .userInitiated) {
            guard let url = try? cache.write(Data(full.utf8), name: "clip-\(changeCount).txt") else { return }
            cache.prune()
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
        }
    }
}
