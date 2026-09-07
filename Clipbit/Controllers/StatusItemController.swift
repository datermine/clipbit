import AppKit
import SwiftUI

/// Owns the `NSStatusItem`: keeps the icon in sync with the monitor, tracks hover for the
/// preview popover, routes clicks, and builds the right-click menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private enum PopoverMode {
        case hidden
        case hover
        case pinned
    }

    private enum TrackingSource: String {
        case button, popover
        static let userInfoKey = "source"
    }

    private let statusItem: NSStatusItem
    private let monitor: ClipboardMonitor
    private let router: ActionRouter
    private let previewModel = PreviewModel()

    private var popover: NSPopover?
    private var mode: PopoverMode = .hidden
    private var pinnedClosedAt: Date?
    private var previousApp: NSRunningApplication?

    private var state: ClipboardState = .initial
    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?
    private var appliedPollInterval: TimeInterval = 0
    private var appliedThumbnailMode = false

    init(monitor: ClipboardMonitor, router: ActionRouter) {
        self.monitor = monitor
        self.router = router
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
    }

    func start() {
        configureButton()
        previewModel.onActivate = { [weak self] modifiers in
            self?.performPrimaryAction(modifiers: modifiers)
        }
        appliedPollInterval = Preferences.pollInterval
        appliedThumbnailMode = Preferences.thumbnailMode
        applyIcon()
        observeDefaults()

        let monitor = self.monitor
        updatesTask = Task { [weak self] in
            let updates = await monitor.updates
            for await state in updates {
                self?.apply(state)
            }
        }
        Task { await monitor.start() }
    }

    #if DEBUG
    func debugShowPopover(pinned: Bool) {
        showPopover(pinned: pinned)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            let popoverFrame = popover?.contentViewController?.view.window?.frame ?? .zero
            let buttonFrame = statusItem.button?.window?.frame ?? .zero
            DebugHooks.logger.info("popover shown=\(self.popover?.isShown == true) mode=\(String(describing: self.mode), privacy: .public) frame=\(NSStringFromRect(popoverFrame), privacy: .public) statusItem=\(NSStringFromRect(buttonFrame), privacy: .public)")
        }
    }
    #endif

    // MARK: - Button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: [TrackingSource.userInfoKey: TrackingSource.button.rawValue]
        )
        button.addTrackingArea(tracking)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        hoverTask?.cancel()

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            closePopover()
            showMenu()
            return
        }

        // Second click on a pinned popover closes it. The transient popover usually closes
        // itself on the mouse-down, so also treat a click right after that close as the toggle.
        if mode == .pinned, popover?.isShown == true {
            closePopover()
            return
        }
        if let closedAt = pinnedClosedAt, Date().timeIntervalSince(closedAt) < 0.5 {
            pinnedClosedAt = nil
            return
        }
        pinnedClosedAt = nil
        performPrimaryAction(modifiers: event.modifierFlags)
    }

    /// The left-click action for the current state, whether it came from the status item or
    /// from clicking the thumbnail inside the preview.
    private func performPrimaryAction(modifiers: NSEvent.ModifierFlags) {
        closePopover()
        switch router.perform(for: state, modifiers: modifiers) {
        case .none:
            break
        case .showPinnedPreview:
            showPopover(pinned: true)
        }
    }

    // MARK: - State

    private func apply(_ newState: ClipboardState) {
        let previous = state
        state = newState
        applyIcon()
        if newState.changeCount != previous.changeCount, previous.changeCount != ClipboardState.initial.changeCount {
            pulse()
        }
        // Refreshes the popover in place if it's open; also prefetches file thumbnails.
        previewModel.update(state: newState, pinned: mode == .pinned)
        #if DEBUG
        DebugHooks.scheduleSnapshots(for: newState)
        #endif
    }

    private func applyIcon() {
        guard let button = statusItem.button else { return }
        if Preferences.thumbnailMode, case .image(let image) = state.content, let thumbnail = image.menuBarThumbnail {
            button.image = thumbnail
        } else {
            button.image = StatusIcon.image(for: state)
        }
        button.setAccessibilityLabel(StatusIcon.accessibilityDescription(for: state))
    }

    /// Brief opacity dip so a new copy is noticeable without looking at the icon.
    private func pulse() {
        guard let button = statusItem.button else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.125
            button.animator().alphaValue = 0.25
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.125
                button.animator().alphaValue = 1
            }
        })
    }

    private func observeDefaults() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.preferencesDidChange() }
        }
    }

    private func preferencesDidChange() {
        let interval = Preferences.pollInterval
        if interval != appliedPollInterval, interval > 0 {
            appliedPollInterval = interval
            let monitor = self.monitor
            Task { await monitor.setInterval(.milliseconds(Int(interval * 1000))) }
        }
        let thumbnailMode = Preferences.thumbnailMode
        if thumbnailMode != appliedThumbnailMode {
            appliedThumbnailMode = thumbnailMode
            applyIcon()
        }
    }

    // MARK: - Hover tracking

    // NSTrackingArea sends `mouseEntered:` / `mouseExited:` to its owner. This class is not an
    // NSResponder, so the selectors must be spelled out: a plain `@objc func mouseEntered(with:)`
    // would export as `mouseEnteredWith:` and AppKit would silently never call it.
    @objc(mouseEntered:)
    func mouseEntered(with event: NSEvent) {
        #if DEBUG
        DebugHooks.logger.debug("mouseEntered source=\(self.trackingSource(of: event).rawValue, privacy: .public) mode=\(String(describing: self.mode), privacy: .public)")
        #endif
        closeTask?.cancel()
        closeTask = nil
        guard trackingSource(of: event) == .button else { return }
        guard mode == .hidden, statusItem.menu == nil else { return }

        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Preferences.hoverDelayMilliseconds))
            guard !Task.isCancelled, let self else { return }
            self.showPopover(pinned: false)
        }
    }

    @objc(mouseExited:)
    func mouseExited(with event: NSEvent) {
        #if DEBUG
        DebugHooks.logger.debug("mouseExited source=\(self.trackingSource(of: event).rawValue, privacy: .public) mode=\(String(describing: self.mode), privacy: .public)")
        #endif
        hoverTask?.cancel()
        hoverTask = nil
        guard mode == .hover else { return }

        // 200 ms grace period; stay open if the pointer moved into the popover itself.
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, self.mode == .hover else { return }
            if self.isMouseInsidePopover() { return }
            self.closePopover()
        }
    }

    private func trackingSource(of event: NSEvent) -> TrackingSource {
        let raw = event.trackingArea?.userInfo?[TrackingSource.userInfoKey] as? String
        return raw.flatMap(TrackingSource.init(rawValue:)) ?? .button
    }

    private func isMouseInsidePopover() -> Bool {
        guard let window = popover?.contentViewController?.view.window, popover?.isShown == true else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    // MARK: - Popover

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.animates = false
        popover.delegate = self

        let hosting = NSHostingController(rootView: PreviewView(model: previewModel))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: [TrackingSource.userInfoKey: TrackingSource.popover.rawValue]
        )
        hosting.view.addTrackingArea(tracking)
        return popover
    }

    private func showPopover(pinned: Bool) {
        guard let button = statusItem.button, statusItem.menu == nil else { return }
        hoverTask?.cancel()
        closeTask?.cancel()

        let popover = self.popover ?? makePopover()
        self.popover = popover
        if popover.isShown {
            popover.close()
        }

        mode = pinned ? .pinned : .hover
        previewModel.isVisible = true
        previewModel.update(state: state, pinned: pinned)

        // Hover: we own the lifetime (mouse exit, any click, or the icon click closes it), so a
        // click on the icon reaches the button instead of being swallowed as a dismissal.
        // Pinned: transient, so Esc and clicking elsewhere dismiss it like a normal popover.
        popover.behavior = pinned ? .transient : .applicationDefined

        if pinned {
            // Activate so the popover can become key: Esc closes it and text is selectable.
            let frontmost = NSWorkspace.shared.frontmostApplication
            previousApp = frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : frontmost
            NSApp.activate(ignoringOtherApps: true)
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if !pinned {
            installOutsideClickMonitor()
        }
        #if DEBUG
        DebugHooks.logger.debug("popover show pinned=\(pinned) changeCount=\(self.state.changeCount)")
        #endif

        if pinned {
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func closePopover() {
        hoverTask?.cancel()
        closeTask?.cancel()
        guard let popover, popover.isShown else {
            mode = .hidden
            previewModel.isVisible = false
            return
        }
        popover.performClose(nil)
    }

    /// Closes the hover popover on a click in any other app (SPEC §4: "or on any click").
    /// Clicks on the status item and inside the popover are ours and handled directly.
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode == .hover else { return }
                self.closePopover()
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        // A close that's immediately followed by a re-show reports isShown == true here.
        guard popover?.isShown != true else { return }
        removeOutsideClickMonitor()
        let wasPinned = mode == .pinned
        #if DEBUG
        DebugHooks.logger.debug("popover did close pinned=\(wasPinned)")
        #endif
        mode = .hidden
        previewModel.isVisible = false
        previewModel.update(state: state, pinned: false)
        if wasPinned {
            pinnedClosedAt = Date()
            restorePreviousApp()
        }
    }

    /// Give focus back to the app that was active before a pinned popover, unless the user
    /// already switched to another app by clicking it (which is what closed the popover).
    private func restorePreviousApp() {
        guard let previous = previousApp else { return }
        previousApp = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard NSApp.isActive, !previous.isTerminated else { return }
            NSApp.yieldActivation(to: previous)
            previous.activate()
        }
    }

    // MARK: - Menu

    private func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let clear = menu.addItem(withTitle: "Clear Clipboard", action: #selector(clearClipboard), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = state.kind != .empty

        let plain = menu.addItem(withTitle: "Copy as Plain Text", action: #selector(copyAsPlainText), keyEquivalent: "")
        plain.target = self
        plain.isEnabled = state.kind == .text || state.kind == .url

        menu.addItem(.separator())

        let thumbnail = menu.addItem(withTitle: "Thumbnail Mode", action: #selector(toggleThumbnailMode), keyEquivalent: "")
        thumbnail.target = self
        thumbnail.state = Preferences.thumbnailMode ? .on : .off

        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off

        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self

        let about = menu.addItem(withTitle: "About Clipbit", action: #selector(showAbout), keyEquivalent: "")
        about.target = self

        let quit = menu.addItem(withTitle: "Quit Clipbit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        return menu
    }

    @objc private func clearClipboard() {
        NSPasteboard.general.clearContents()
        let monitor = self.monitor
        Task { await monitor.pollNow() }
    }

    /// Rewrites the pasteboard with only the `.string` flavor, dropping RTF/HTML.
    @objc private func copyAsPlainText() {
        let pasteboard = NSPasteboard.general
        let text: String
        switch state.content {
        case .text(let summary):
            if pasteboard.changeCount == state.changeCount, let current = pasteboard.string(forType: .string) {
                text = current
            } else {
                text = summary.fullText
            }
        case .url(let summary):
            text = summary.url.absoluteString
        default:
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let monitor = self.monitor
        Task { await monitor.pollNow() }
    }

    @objc private func toggleThumbnailMode() {
        Preferences.thumbnailMode.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login"
            alert.runModal()
        }
    }

    @objc private func openSettings() {
        SettingsOpener.open()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Clipbit",
            .credits: NSAttributedString(string: "Shows what's on the clipboard, previews it on hover, and does the obvious thing on click."),
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
