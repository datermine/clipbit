# Clipbit

A macOS menu bar app that shows *what kind of thing* is on the clipboard right now,
previews it on hover, and does the obvious action on click. No history, no windows beyond
the popover and Settings. See [SPEC.md](SPEC.md) for the full design.

## Build & run

Requires Xcode 16 or later (macOS 14.0 deployment target).

```sh
make run          # builds Release into ./build and launches ClipBit.app
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
- **Privacy:** nothing leaves your Mac except a favicon request while a URL preview is on
  screen. See [PRIVACY.md](PRIVACY.md).
- **Source app** in the footer is best-effort: it uses `org.nspasteboard.source` when the
  copying app declares it, otherwise the frontmost app at the moment the change was noticed.
- **Favicons** are fetched only while the preview is on screen, never merely because a URL
  was copied.
- Exported images/text for Preview and the editor live in `~/Library/Caches/<bundle id>/`
  (inside the sandbox container) and are pruned to the last five files.
- The bundle identifier is `com.georgemike.ClipBit`; change it in `project.yml`.
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
`/usr/bin/log stream --predicate 'subsystem == "com.georgemike.ClipBit"' --level debug`.

## Distribution

The source here is free to build and use. The Mac App Store version is the same app, signed
and kept up to date by Apple, and buying it supports development. `make release` archives,
exports, and uploads to App Store Connect using an App Store Connect API key
(`scripts/release-macos.sh`; `make release-dry` stops at a local `.pkg`). The key's `.p8`
lives outside the repo and its key/issuer IDs come from an untracked `.release.env`
(`ASC_KEY_ID`, `ASC_ISSUER_ID`). Signing is automatic
for team `39M246A2UR`; the App Store icon set lives
in `Clipbit/Assets.xcassets`, and `Clipbit/PrivacyInfo.xcprivacy` declares the required-reason
APIs (UserDefaults for settings, file timestamps for cache pruning).

## Brand

| Role | Hex |
|---|---|
| Gradient start (top-left) | `#FFB347` tangerine |
| Gradient end (bottom-right) | `#FF2E88` raspberry |
| Outline and iconography | `#1E1B4B` ink navy |

The logo is a tangerine-to-raspberry gradient square with the clipboard glyph and border in
ink navy. The glyph is `content_paste` from the Material Icons font. Masters live in `internal/` (`logo.1024.png`, `logo.png`, `logo.128.png`); the App
Store icon set in `Clipbit/Assets.xcassets` is derived from the 1024 master on Apple's macOS
icon template.

## License

[MIT](LICENSE) © 2026 George Mike.
