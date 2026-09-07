# Clipboard Indicator — Spec

A macOS menu bar app that shows *what kind of thing* is on the clipboard right now, previews it on hover, and does the obvious action on click. No history, no UI beyond the status item.

Working name: **Clipbit** (placeholder).

---

## 1. Scope

**In**
- One `NSStatusItem` whose icon reflects the current pasteboard content type
- Hover preview (popover) of the current item
- Single click → type-appropriate action
- Right-click → small utility menu
- Respect "concealed" pasteboard content (password managers)

**Out (v1)**
- Clipboard history
- Editing or transforming clipboard contents
- iCloud / Universal Clipboard awareness beyond what the pasteboard already exposes
- Any window besides the popover and Settings

---

## 2. Content classification

Poll `NSPasteboard.general.changeCount` on a 0.5 s timer (there is no pasteboard-change notification on macOS). When it changes, classify the **first** pasteboard item using this priority order. First match wins.

| # | Kind        | Detection                                                                                  |
|---|-------------|--------------------------------------------------------------------------------------------|
| 0 | Concealed   | Item declares `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType`         |
| 1 | File        | `.fileURL` type present → resolve to `URL`; also: plain text that is an absolute path and `FileManager.fileExists` |
| 2 | Image       | Any of `.png`, `.tiff`, `public.jpeg`, `public.heic`; or File kind whose UTI conforms to `public.image` (treated as File, but see §5) |
| 3 | URL         | `.URL` type present; or plain text that parses as `URL` with scheme `http`/`https`/`mailto`/`file` and a host |
| 4 | Text        | `.string` present (also covers `.rtf`/`.html` — always read the `.string` representation) |
| 5 | Other       | Pasteboard non-empty but nothing above matched (e.g. custom app types)                    |
| 6 | Empty       | `pasteboardItems` is nil/empty                                                              |

Notes
- Never read pasteboard content if `changeCount` hasn't changed (avoid touching data from apps that mark it transient).
- Multi-item pasteboards (e.g. 12 files copied in Finder): classify from the first item, but remember the count for the preview ("+11 more").
- Cap text reads at 10 KB — read only what the preview needs.

---

## 3. The icon

Use SF Symbols rendered as template images so they follow menu bar light/dark and accessibility contrast.

| Kind      | Symbol                          |
|-----------|---------------------------------|
| Empty     | `clipboard` (outline)           |
| Text      | `doc.text`                      |
| URL       | `link`                          |
| Image     | `photo`                         |
| File      | `doc` (folder: `folder`)        |
| Other     | `questionmark.square.dashed`    |
| Concealed | `lock`                          |

Behaviour
- Brief "pulse" (0.25 s opacity dip) when the clipboard changes so you notice a new copy without looking.
- Multi-item: small numeric badge is tempting but unreadable at 18 pt — skip it; the count goes in the preview.
- **Optional setting — "Thumbnail mode"**: for Image kind, replace the symbol with a 16×16 downscaled thumbnail of the actual image (non-template, rounded 2 pt). Off by default; it's fun but breaks the visual consistency of the menu bar.

---

## 4. Hover preview

`NSStatusBarButton` has no hover API. Add an `NSTrackingArea` (`.mouseEnteredAndExited`, `.activeAlways`) to `statusItem.button`. On enter, start a **150 ms** debounce; on exit, cancel and close. Show an `NSPopover` (`.transient` behaviour, `preferredEdge: .minY`) anchored to the button. Popover closes on mouse exit + 200 ms grace period, or on any click.

The popover is a single compact view, max width 320 pt.

| Kind      | Preview content                                                                                                  |
|-----------|------------------------------------------------------------------------------------------------------------------|
| Text      | `first16 + " … " + last16`. If length ≤ 32, show the whole string. Collapse runs of whitespace to a single space; render newlines as `⏎`. Secondary line: `N characters · M lines`. |
| URL       | Favicon (fetched async, cached; fallback `globe`), host in bold, then the path truncated middle-out to fit one line. |
| File      | Finder icon for the file (`NSWorkspace.shared.icon(forFile:)`, 32 pt), filename in bold, parent folder path abbreviated with `~`. If it's an image file, use a real thumbnail via `QuickLookThumbnailing` instead of the generic icon. Multi-select: "+N more" below. |
| Image     | Thumbnail, aspect-fit inside 280×160, plus `W × H px` and the source type (PNG/TIFF/JPEG). Cache the thumbnail keyed by `changeCount`. |
| Other     | List of the item's UTIs, one per line, monospaced.                                                               |
| Concealed | Lock icon and "Concealed by [source app if known]". Never show content.                                          |
| Empty     | "Clipboard is empty".                                                                                            |

Footer (all kinds except Empty): source app name + icon if `NSPasteboard` metadata identifies it (best-effort — not always available), and a one-line hint of the click action, e.g. "Click to reveal in Finder".

Rendering: build previews off the main thread (image decode, QuickLook, favicon), then dispatch to main. The popover must not stall the menu bar.

---

## 5. Click actions

Left click on the status item:

| Kind      | Action                                                                                                                      |
|-----------|-----------------------------------------------------------------------------------------------------------------------------|
| File      | `NSWorkspace.shared.activateFileViewerSelecting([url])` (reveal in Finder, selected). Multi: pass all URLs.                   |
| Image     | Write the image data to `~/Library/Caches/<bundle>/clip-<changeCount>.png` (or original format if it's JPEG/HEIC), then open with Preview via `NSWorkspace.shared.open([url], withApplicationAt: previewAppURL, ...)`. Fall back to `open(url)` (default handler) if Preview isn't found. Prune the cache to the last 5 files. |
| URL       | `NSWorkspace.shared.open(url)` — default browser / mail client / etc.                                                        |
| Text      | Open the popover pinned (i.e. same preview but with full text, scrollable, max 320×400). Second click or Esc closes it.       |
| Other     | Same as Text but showing the UTI list.                                                                                     |
| Concealed | No action; preview just says it's concealed.                                                                                |
| Empty     | No action.                                                                                                                  |

Modifiers
- ⌥-click: Text → open in default text editor (write temp `.txt`, `open`). File → open the file instead of revealing. URL → copy to clipboard? (no-op, it's already there) → open in a *new private window* is not scriptable reliably; skip. Image → same as plain click.
- Right-click / ctrl-click → menu (§6).

---

## 6. Right-click menu

- Clear clipboard (`NSPasteboard.general.clearContents()`)
- Copy as plain text (Text/URL kinds only — strips RTF/HTML flavors by rewriting the pasteboard with just `.string`)
- ─
- Thumbnail mode ✓/✗
- Launch at login ✓/✗ (`SMAppService.mainApp`)
- ─
- About
- Quit

---

## 7. Settings

Keep it to a tiny `Settings` scene (SwiftUI) reachable only from the menu:
- Poll interval: 0.25 / 0.5 / 1 s (default 0.5)
- Thumbnail mode toggle
- Show source app in preview toggle
- Hover delay: 100 / 150 / 300 ms

---

## 8. Architecture

- Swift, AppKit for the status item + popover, SwiftUI inside the popover and Settings.
- `LSUIElement = YES` (no Dock icon, no main menu).
- Single `ClipboardMonitor` actor: owns the timer, publishes `ClipboardState` (kind, summary fields, thumbnail, changeCount).
- `StatusItemController`: subscribes to state, updates icon, owns tracking area + popover.
- `ActionRouter`: `perform(for state: ClipboardState, modifiers:)`.
- No persistence beyond `UserDefaults` for settings and the image cache directory.

Sandbox / distribution
- Reading the general pasteboard is allowed under App Sandbox.
- Reveal-in-Finder for arbitrary file URLs works sandboxed.
- Opening an image in Preview from your own cache directory works sandboxed.
- Launch-at-login via `SMAppService` is fine sandboxed.
- So MAS is viable; if you go Developer ID direct instead, nothing changes in the design.

Performance targets
- Idle CPU < 0.1% (polling `changeCount` is a cheap integer read).
- Icon updates within one poll interval of a copy.
- Popover appears within 50 ms of the hover delay elapsing for cached previews.

---

## 9. Edge cases

- **Universal Clipboard from iPhone**: content arrives normally; source app is unknown — footer just omits it.
- **Huge text** (e.g. copying a whole file): read only the first and last 10 KB for the preview counts; report "≥ N characters" if truncated.
- **Copied from Terminal**: often plain text that looks like a path → File detection via `fileExists` handles it; if the path doesn't exist, it's Text.
- **Screenshot to clipboard** (⌃⇧⌘4): arrives as PNG/TIFF → Image. Very common case, make sure the thumbnail path is fast.
- **Finder copy of an image file**: classified as File (reveal on click), but the preview uses a real thumbnail so it *looks* like an image. ⌥-click opens it.
- **Pasteboard changed while popover open**: refresh the popover contents in place.
- **Menu bar hidden (fullscreen apps)**: tracking area won't fire; nothing to do.
- **Bartender / Ice** hiding the icon: the icon may live in a collapsed section; hover still works when visible. Document that it wants to be pinned.

---

## 10. Milestones

1. Status item + monitor + icon swapping for all kinds
2. Click actions
3. Hover popover with previews (image, text, URL, file)
4. Concealed handling, right-click menu, launch at login
5. Thumbnail mode, settings, cache pruning, polish

