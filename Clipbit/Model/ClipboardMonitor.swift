import AppKit

/// Owns the polling timer and publishes `ClipboardState` whenever
/// `NSPasteboard.general.changeCount` moves. All pasteboard reads happen here, off the
/// main thread, and only when the change count actually changed.
actor ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private var interval: Duration
    private var lastChangeCount: Int?
    private var pollTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<ClipboardState>.Continuation] = [:]
    private(set) var state: ClipboardState = .initial

    init(pasteboard: NSPasteboard = .general, interval: Duration = .milliseconds(500)) {
        self.pasteboard = pasteboard
        self.interval = interval
    }

    /// Yields the current state immediately, then every subsequent change.
    var updates: AsyncStream<ClipboardState> {
        let (stream, continuation) = AsyncStream.makeStream(of: ClipboardState.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        continuation.yield(state)
        return stream
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: await self.interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func setInterval(_ newInterval: Duration) {
        interval = newInterval
    }

    /// Re-check right away, e.g. after Clipbit itself rewrote the pasteboard.
    func pollNow() async {
        await poll()
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func poll() async {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        let isInitialRead = lastChangeCount == nil
        lastChangeCount = count

        // The frontmost app when we notice a change is the best available guess for the source.
        // On the initial read at launch that guess would be meaningless, so skip it.
        let frontmost: SourceApp? = isInitialRead ? nil : await MainActor.run { SourceApp.frontmost() }
        let newState = ClipboardClassifier.classify(pasteboard: pasteboard, changeCount: count, frontmostApp: frontmost)
        state = newState
        for continuation in subscribers.values {
            continuation.yield(newState)
        }
    }
}
