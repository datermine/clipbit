import SwiftUI
import AppKit

/// The popover body: one compact card per clipboard kind plus a footer with the source app
/// and a hint for the click action (SPEC §4).
struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    @AppStorage(Preferences.Key.showSourceApp) private var showSourceApp = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if model.state.kind != .empty {
                Divider()
                footer
            }
        }
        .padding(12)
        .frame(minWidth: model.isPinned ? PreviewMetrics.cardWidth : 200, maxWidth: PreviewMetrics.cardWidth, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state.content {
        case .empty:
            Text("Clipboard is empty")
                .foregroundStyle(.secondary)
        case .concealed:
            ConcealedPreview(app: model.state.sourceApp)
        case .text(let summary):
            TextPreview(summary: summary, pinned: model.isPinned)
        case .url(let summary):
            URLPreview(summary: summary, favicon: model.favicon)
        case .image(let summary):
            ImagePreview(summary: summary, activate: model.activate)
        case .file(let summary):
            FilePreview(summary: summary, icon: model.fileIcon, thumbnail: model.fileThumbnail, activate: model.activate)
        case .other(let summary):
            OtherPreview(summary: summary, pinned: model.isPinned)
        }
    }

    @ViewBuilder
    private var footer: some View {
        let app = showSourceApp ? model.state.sourceApp : nil
        Group {
            if PreviewMetrics.footerFitsOneLine(appName: app?.name, hint: hint) {
                HStack(spacing: 6) {
                    sourceAppLabel(app)
                    Spacer(minLength: 12)
                    hintLabel
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    sourceAppLabel(app)
                    hintLabel
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func sourceAppLabel(_ app: SourceApp?) -> some View {
        if let app {
            HStack(spacing: 6) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 14, height: 14)
                }
                Text(app.name)
                    .lineLimit(1)
            }
        }
    }

    private var hintLabel: some View {
        Text(hint)
            .lineLimit(1)
            .foregroundStyle(.tertiary)
    }

    private var hint: String {
        switch model.state.content {
        case .empty:
            return ""
        case .concealed:
            return "No action"
        case .text:
            return model.isPinned ? "Click again or press Esc to close" : "Click to expand · ⌥-click to open in editor"
        case .url(let summary):
            return summary.isMail ? "Click to open in Mail" : "Click to open in browser"
        case .image:
            return "Click to open in Preview"
        case .file:
            return "Click to reveal in Finder · ⌥-click to open"
        case .other:
            return model.isPinned ? "Click again or press Esc to close" : "Click to expand"
        }
    }
}

// MARK: - Per-kind previews

private struct TextPreview: View {
    let summary: TextSummary
    let pinned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if pinned {
                ScrollView(.vertical) {
                    Text(summary.fullText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: PreviewMetrics.scrollHeight(for: summary.fullText, font: .preferredFont(forTextStyle: .body)))
            } else {
                Text(summary.preview)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(stats)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stats: String {
        let bound = summary.isTruncated ? "≥ " : ""
        let characters = summary.characterCount == 1 ? "character" : "characters"
        let lines = summary.lineCount == 1 ? "line" : "lines"
        return "\(bound)\(summary.characterCount.formatted()) \(characters) · \(bound)\(summary.lineCount.formatted()) \(lines)"
    }
}

private struct URLPreview: View {
    let summary: URLSummary
    let favicon: NSImage?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if let favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: summary.isMail ? "envelope" : "globe")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(summary.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct ImagePreview: View {
    let summary: ImageSummary
    let activate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let thumbnail = summary.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .clickable(help: "Open in Preview", action: activate)
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            Text("\(Int(summary.pixelSize.width)) × \(Int(summary.pixelSize.height)) px · \(summary.format)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FilePreview: View {
    let summary: FileSummary
    let icon: NSImage?
    let thumbnail: NSImage?
    let activate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if summary.isImage, let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .clickable(help: "Reveal in Finder", action: activate)
                nameColumn
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Group {
                        if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                        } else {
                            Image(systemName: summary.isDirectory ? "folder" : "doc")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .clickable(help: "Reveal in Finder", action: activate)
                    nameColumn
                }
            }
            if summary.count > 1 {
                Text("+\(summary.count - 1) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.name)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(summary.abbreviatedParent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct OtherPreview: View {
    let summary: OtherSummary
    let pinned: Bool

    var body: some View {
        if pinned {
            let text = summary.types.joined(separator: "\n")
            ScrollView(.vertical) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: PreviewMetrics.scrollHeight(for: text, font: PreviewMetrics.monospacedCaptionFont))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(summary.types.enumerated()), id: \.offset) { _, type in
                    Text(type)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

private struct ConcealedPreview: View {
    let app: SourceApp?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock")
                .foregroundStyle(.secondary)
            if let app {
                Text("Concealed by \(app.name)")
            } else {
                Text("Concealed content")
            }
        }
    }
}

// MARK: - Click-through

private extension View {
    /// Makes a thumbnail act like the status item: pointing-hand cursor, tooltip, and the
    /// primary action on click.
    func clickable(help: String, action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help(help)
    }
}

// MARK: - Layout metrics

/// Text measurement with AppKit so the card's height and footer layout are decided
/// deterministically, independent of SwiftUI's ideal-size pass (SPEC §4/§5: max 320×400).
enum PreviewMetrics {
    static let cardWidth: CGFloat = 320
    static let padding: CGFloat = 12
    static var contentWidth: CGFloat { cardWidth - 2 * padding }
    static let maxScrollHeight: CGFloat = 320

    static var monospacedCaptionFont: NSFont {
        .monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)
    }

    static func scrollHeight(for text: String, font: NSFont) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return min(maxScrollHeight, ceil(bounds.height) + 8)
    }

    static func footerFitsOneLine(appName: String?, hint: String) -> Bool {
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var width = (hint as NSString).size(withAttributes: attributes).width
        if let appName {
            width += 14 + 6 + (appName as NSString).size(withAttributes: attributes).width + 12
        }
        return width <= contentWidth
    }
}
