import AppKit
import XCTest
@testable import Clipbit

final class ClipboardClassifierTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.datermine.Clipbit.tests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    private func classify() -> ClipboardState {
        ClipboardClassifier.classify(pasteboard: pasteboard, changeCount: pasteboard.changeCount, frontmostApp: nil)
    }

    private func write(_ item: NSPasteboardItem) {
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private func temporaryFile(named name: String, contents: Data = Data("x".utf8)) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try contents.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Text helpers

    func testCollapseWhitespaceAndNewlines() {
        XCTAssertEqual(ClipboardClassifier.collapse("a   b\n\tc"), "a b⏎ c")
        XCTAssertEqual(ClipboardClassifier.collapse("  lead and trail  "), "lead and trail")
        XCTAssertEqual(ClipboardClassifier.collapse("one\n\ntwo"), "one⏎⏎two")
    }

    func testLineCount() {
        XCTAssertEqual(ClipboardClassifier.lineCount(of: ""), 0)
        XCTAssertEqual(ClipboardClassifier.lineCount(of: "abc"), 1)
        XCTAssertEqual(ClipboardClassifier.lineCount(of: "abc\n"), 1)
        XCTAssertEqual(ClipboardClassifier.lineCount(of: "a\nb"), 2)
        XCTAssertEqual(ClipboardClassifier.lineCount(of: "a\r\nb\r\n"), 2)
    }

    func testShortTextPreviewIsShownWhole() {
        let summary = ClipboardClassifier.textSummary(string: "Hello, world!", isTruncated: false)
        XCTAssertEqual(summary.preview, "Hello, world!")
        XCTAssertEqual(summary.characterCount, 13)
        XCTAssertEqual(summary.lineCount, 1)
        XCTAssertFalse(summary.isTruncated)
    }

    func testLongTextPreviewUsesFirstAndLast16() {
        let head = String(repeating: "x", count: 16)
        let tail = String(repeating: "y", count: 16)
        let summary = ClipboardClassifier.textSummary(string: head + " the middle part " + tail, isTruncated: false)
        XCTAssertEqual(summary.preview, head + " … " + tail)
    }

    func testHugeTextReadsOnlyHeadAndTail() {
        let data = Data(repeating: UInt8(ascii: "a"), count: 100_000)
        let summary = ClipboardClassifier.textSummary(utf8: data)
        XCTAssertTrue(summary.isTruncated)
        XCTAssertEqual(summary.characterCount, 2 * ClipboardClassifier.textReadCap)
        XCTAssertTrue(summary.fullText.contains("only the first and last"))
    }

    func testHugeTextDropsCharacterBrokenByTheCut() {
        var data = Data(repeating: UInt8(ascii: "a"), count: ClipboardClassifier.textReadCap - 1)
        data.append(contentsOf: Array("é".utf8)) // straddles the cap boundary
        data.append(Data(repeating: UInt8(ascii: "b"), count: 40_000))
        let summary = ClipboardClassifier.textSummary(utf8: data)
        XCTAssertFalse(summary.fullText.contains("\u{FFFD}"))
        XCTAssertTrue(summary.isTruncated)
    }

    // MARK: - Classification

    func testEmptyPasteboard() {
        pasteboard.clearContents()
        XCTAssertEqual(classify().kind, .empty)
    }

    func testPlainText() {
        pasteboard.clearContents()
        pasteboard.setString("hello there", forType: .string)
        let state = classify()
        guard case .text(let summary) = state.content else { return XCTFail("expected text, got \(state.kind)") }
        XCTAssertEqual(summary.preview, "hello there")
        XCTAssertEqual(state.itemCount, 1)
    }

    func testWebURLInPlainText() {
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/some/path?q=1#frag\n", forType: .string)
        let state = classify()
        guard case .url(let summary) = state.content else { return XCTFail("expected url, got \(state.kind)") }
        XCTAssertEqual(summary.title, "example.com")
        XCTAssertEqual(summary.subtitle, "/some/path?q=1#frag")
        XCTAssertFalse(summary.isMail)
    }

    func testMailtoInPlainText() {
        pasteboard.clearContents()
        pasteboard.setString("mailto:someone@example.com", forType: .string)
        let state = classify()
        guard case .url(let summary) = state.content else { return XCTFail("expected url, got \(state.kind)") }
        XCTAssertEqual(summary.title, "someone@example.com")
        XCTAssertTrue(summary.isMail)
    }

    func testSchemeWithoutHostIsText() {
        pasteboard.clearContents()
        pasteboard.setString("https://", forType: .string)
        XCTAssertEqual(classify().kind, .text)
    }

    func testURLTypeBeatsStringType() {
        let item = NSPasteboardItem()
        item.setString("Apple", forType: .string)
        item.setString("https://www.apple.com/", forType: .URL)
        write(item)
        let state = classify()
        guard case .url(let summary) = state.content else { return XCTFail("expected url, got \(state.kind)") }
        XCTAssertEqual(summary.title, "www.apple.com")
    }

    func testExistingPathInPlainTextIsFile() throws {
        let url = try temporaryFile(named: "note.txt")
        pasteboard.clearContents()
        pasteboard.setString(url.path + "\n", forType: .string)
        let state = classify()
        guard case .file(let summary) = state.content else { return XCTFail("expected file, got \(state.kind)") }
        XCTAssertEqual(summary.primary.standardizedFileURL, url.standardizedFileURL)
        XCTAssertFalse(summary.isDirectory)
        XCTAssertFalse(summary.isImage)
    }

    func testDirectoryPathIsFileKindWithDirectoryFlag() {
        pasteboard.clearContents()
        pasteboard.setString(FileManager.default.temporaryDirectory.path, forType: .string)
        let state = classify()
        guard case .file(let summary) = state.content else { return XCTFail("expected file, got \(state.kind)") }
        XCTAssertTrue(summary.isDirectory)
    }

    func testMissingPathIsText() {
        pasteboard.clearContents()
        pasteboard.setString("/no/such/path/\(UUID().uuidString).txt", forType: .string)
        XCTAssertEqual(classify().kind, .text)
    }

    func testFileURLsIncludingImageAndMultipleItems() throws {
        let png = try XCTUnwrap(Self.makePNG(width: 8, height: 6))
        let image = try temporaryFile(named: "picture.png", contents: png)
        let text = try temporaryFile(named: "notes.txt")
        pasteboard.clearContents()
        pasteboard.writeObjects([image as NSURL, text as NSURL])
        let state = classify()
        guard case .file(let summary) = state.content else { return XCTFail("expected file, got \(state.kind)") }
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(state.itemCount, 2)
        XCTAssertTrue(summary.name.hasSuffix("picture.png"))
        XCTAssertTrue(summary.isImage)
    }

    func testPNGImageData() throws {
        let png = try XCTUnwrap(Self.makePNG(width: 40, height: 30))
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        let state = classify()
        guard case .image(let summary) = state.content else { return XCTFail("expected image, got \(state.kind)") }
        XCTAssertEqual(summary.format, "PNG")
        XCTAssertEqual(summary.fileExtension, "png")
        XCTAssertEqual(summary.pixelSize, CGSize(width: 40, height: 30))
        XCTAssertNotNil(summary.thumbnail)
        XCTAssertNotNil(summary.menuBarThumbnail)
        XCTAssertEqual(summary.menuBarThumbnail?.size, NSSize(width: 16, height: 16))
    }

    func testTIFFExportsAsPNG() throws {
        let png = try XCTUnwrap(Self.makePNG(width: 4, height: 4))
        let tiff = try XCTUnwrap(NSBitmapImageRep(data: png)?.tiffRepresentation)
        pasteboard.clearContents()
        pasteboard.setData(tiff, forType: .tiff)
        let state = classify()
        guard case .image(let summary) = state.content else { return XCTFail("expected image, got \(state.kind)") }
        XCTAssertEqual(summary.format, "TIFF")
        let export = ExportCache.exportRepresentation(of: summary)
        XCTAssertEqual(export.fileExtension, "png")
        XCTAssertEqual(Array(export.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testConcealedWinsOverEverything() {
        let item = NSPasteboardItem()
        item.setString("hunter2", forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        write(item)
        XCTAssertEqual(classify().kind, .concealed)
    }

    func testTransientIsConcealed() {
        let item = NSPasteboardItem()
        item.setString("temp", forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        write(item)
        XCTAssertEqual(classify().kind, .concealed)
    }

    func testCustomTypeOnlyIsOther() {
        let item = NSPasteboardItem()
        item.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.custom-blob"))
        write(item)
        let state = classify()
        guard case .other(let summary) = state.content else { return XCTFail("expected other, got \(state.kind)") }
        XCTAssertEqual(summary.types, ["com.example.custom-blob"])
    }

    func testRTFOnlyFallsBackToConvertedText() throws {
        let attributed = NSAttributedString(string: "Rich text")
        let rtf = try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]))
        let item = NSPasteboardItem()
        item.setData(rtf, forType: .rtf)
        write(item)
        let state = classify()
        guard case .text(let summary) = state.content else { return XCTFail("expected text, got \(state.kind)") }
        XCTAssertEqual(summary.preview, "Rich text")
    }

    // MARK: - Helpers

    private static func makePNG(width: Int, height: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        for y in 0..<height {
            for x in 0..<width {
                rep.setColor(NSColor(red: CGFloat(x) / CGFloat(width), green: 0.4, blue: CGFloat(y) / CGFloat(height), alpha: 1), atX: x, y: y)
            }
        }
        return rep.representation(using: .png, properties: [:])
    }
}

final class HomeDirectoryTests: XCTestCase {
    func testRealHomeIsNotTheSandboxContainer() {
        XCTAssertFalse(HomeDirectory.real.contains("/Library/Containers/"))
        XCTAssertTrue(HomeDirectory.real.hasPrefix("/"))
    }

    func testTildeExpansionAndAbbreviation() {
        XCTAssertEqual(HomeDirectory.expandingTilde(in: "~/Documents"), HomeDirectory.real + "/Documents")
        XCTAssertEqual(HomeDirectory.expandingTilde(in: "~"), HomeDirectory.real)
        XCTAssertEqual(HomeDirectory.expandingTilde(in: "/tmp"), "/tmp")
        XCTAssertEqual(HomeDirectory.abbreviatingWithTilde(HomeDirectory.real + "/Documents/x"), "~/Documents/x")
        XCTAssertEqual(HomeDirectory.abbreviatingWithTilde("/tmp/x"), "/tmp/x")
    }

    func testTildePathOnTheClipboardIsDetectedAsFile() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.datermine.Clipbit.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("~", forType: .string)
        let state = ClipboardClassifier.classify(pasteboard: pasteboard, changeCount: pasteboard.changeCount, frontmostApp: nil)
        guard case .file(let summary) = state.content else { return XCTFail("expected file, got \(state.kind)") }
        XCTAssertTrue(summary.isDirectory)
        XCTAssertEqual(summary.primary.path, HomeDirectory.real)
    }
}

final class StatusItemControllerTests: XCTestCase {
    /// The tracking area on the status button delivers `mouseEntered:`/`mouseExited:` to the
    /// controller. Without explicit `@objc(...)` selectors those would export as
    /// `mouseEnteredWith:` and hover would never fire.
    func testControllerRespondsToTrackingAreaSelectors() {
        XCTAssertTrue(StatusItemController.instancesRespond(to: NSSelectorFromString("mouseEntered:")))
        XCTAssertTrue(StatusItemController.instancesRespond(to: NSSelectorFromString("mouseExited:")))
    }
}
