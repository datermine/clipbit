import AppKit
import Combine

/// Observable bridge between `ClipboardState` and the SwiftUI popover. Loads the slow bits
/// (favicon, QuickLook thumbnail) asynchronously so the popover never waits on them.
@MainActor
final class PreviewModel: ObservableObject {
    @Published private(set) var state: ClipboardState = .initial
    @Published private(set) var isPinned = false
    @Published private(set) var favicon: NSImage?
    @Published private(set) var fileIcon: NSImage?
    @Published private(set) var fileThumbnail: NSImage?

    /// Set by the controller while the popover is on screen. Favicons are only fetched then,
    /// so merely copying a URL never touches the network.
    var isVisible = false {
        didSet { if isVisible { loadFavicon() } }
    }

    /// Invoked when the user clicks the thumbnail inside the preview; wired by the controller
    /// to the same action as a click on the status item.
    var onActivate: ((NSEvent.ModifierFlags) -> Void)?

    private var faviconChangeCount: Int?
    private var faviconTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?

    func update(state newState: ClipboardState, pinned: Bool) {
        let changed = newState.changeCount != state.changeCount
        state = newState
        isPinned = pinned
        guard changed else { return }

        favicon = nil
        fileIcon = nil
        fileThumbnail = nil
        faviconChangeCount = nil
        faviconTask?.cancel()
        thumbnailTask?.cancel()

        if case .file(let file) = newState.content {
            fileIcon = NSWorkspace.shared.icon(forFile: file.primary.path)
            if file.isImage {
                let url = file.primary
                let changeCount = newState.changeCount
                thumbnailTask = Task { [weak self] in
                    let image = await FileThumbnailCache.shared.thumbnail(for: url)
                    guard !Task.isCancelled, let self, self.state.changeCount == changeCount else { return }
                    self.fileThumbnail = image
                }
            }
        }

        if isVisible { loadFavicon() }
    }

    func activate() {
        onActivate?(NSEvent.modifierFlags)
    }

    private func loadFavicon() {
        guard case .url(let summary) = state.content, faviconChangeCount != state.changeCount else { return }
        let changeCount = state.changeCount
        faviconChangeCount = changeCount
        faviconTask = Task { [weak self] in
            let image = await FaviconCache.shared.favicon(for: summary.url)
            guard !Task.isCancelled, let self, self.state.changeCount == changeCount else { return }
            self.favicon = image
        }
    }
}
