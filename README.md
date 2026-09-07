# Clipbit

A macOS menu bar app that shows *what kind of thing* is on the clipboard right now,
previews it on hover, and does the obvious action on click. No history, no windows beyond
the popover and Settings. See [SPEC.md](SPEC.md) for the full design.

## Build & run

Requires Xcode 16 or later (macOS 14.0 deployment target).

```sh
make run          # builds Release into ./build and launches Clipbit.app
make test         # runs the unit tests (classifier, text summaries, home-directory helpers)
```

Or open `Clipbit.xcodeproj` in Xcode and run the `Clipbit` scheme. The project file is
generated from `project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen);
run `make generate` after adding or removing source files (the committed `.xcodeproj`
works without xcodegen installed).

## What it does

| Clipboard holds | Icon | Hover preview | Click |
|---|---|---|---|
| Nothing | `clipboard` | "Clipboard is empty" | — |
| Text | `doc.text` | `first16 … last16`, character/line counts | Expand full text in a pinned popover (⌥-click: open in editor) |
| URL | `link` | favicon, host, path | Open in default browser / mail client |
| Image | `photo` | thumbnail, `W × H px · PNG` | Open in Preview |
| File(s) | `doc` / `folder` | Finder icon or QuickLook thumbnail, name, folder, "+N more" | Reveal in Finder (⌥-click: open) |
| Custom types | `questionmark.square.dashed` | list of UTIs | Expand |
| Concealed (password managers) | `lock` | "Concealed by …" | — |

Right-click (or ⌃-click) for Clear Clipboard, Copy as Plain Text, Thumbnail Mode,
Launch at Login, Settings, About (opens this repository) and Quit.

## Notes

- **Bartender / Ice:** the hover preview needs the icon to be visible, so pin Clipbit
  rather than letting it collapse into a hidden section.
- **Sandbox:** the app is sandboxed (`Supporting/Clipbit.entitlements`) and ready for the
  Mac App Store. Everything in the spec works sandboxed; nothing changes for Developer ID.
- **Source app** in the footer is best-effort: it uses `org.nspasteboard.source` when the
  copying app declares it, otherwise the frontmost app at the moment the change was noticed.
- **Favicons** are fetched only while the preview is on screen, never merely because a URL
  was copied.
- Exported images/text for Preview and the editor live in `~/Library/Caches/<bundle id>/`
  (inside the sandbox container) and are pruned to the last five files.
- The bundle identifier is `com.datermine.Clipbit`; change it in `project.yml`.
- **Settings** is a SwiftUI `Settings` scene. It's opened from the menu via the responder
  chain; if that doesn't produce a window, the same view is shown in a plain window.

## Architecture

| Type | Role |
|---|---|
| `ClipboardMonitor` (actor) | Polls `changeCount` on a timer, reads the pasteboard only when it changed, publishes `ClipboardState` via an `AsyncStream`. |
| `ClipboardClassifier` | Pure classification of the first pasteboard item into `ClipboardContent` (concealed → file → image → URL → text → other). |
| `StatusItemController` | Owns the `NSStatusItem`, icon updates and pulse, hover tracking area, hover/pinned `NSPopover`, right-click menu. |
| `ActionRouter` | Click actions per kind (reveal, open, Preview export, pinned preview). |
| `PreviewModel` / `PreviewView` | SwiftUI popover content; loads favicons and QuickLook thumbnails asynchronously. |
| `SettingsView` | SwiftUI settings form backed by `@AppStorage`. |

## Development hooks (Debug builds only)

Set these environment variables when launching the Debug binary directly:

| Variable | Effect |
|---|---|
| `CLIPBIT_DEBUG_POPOVER=pinned` / `hover` | Shows the popover 1.5 s after launch and logs its frame. |
| `CLIPBIT_DEBUG_SNAPSHOTS=1` | Renders the preview card for every clipboard change to PNGs in the app's temp directory (paths logged). |
| `CLIPBIT_DEBUG_SETTINGS=1` | Opens Settings after launch and logs the visible windows. |

Logs use the bundle identifier as subsystem:
`/usr/bin/log stream --predicate 'subsystem == "com.datermine.Clipbit"' --level debug`.

## License

[MIT](LICENSE) © 2026 George Mike.
