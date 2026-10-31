import XCTest
@testable import ClipFlowCore

final class CapturePolicyTests: XCTestCase {
    var settings = CaptureSettings(isPaused: false, excludedBundleIDs: ["com.1password.1password"],
                                   captureImages: true, captureFiles: true, sensitiveHandling: .maskAndExpire)

    func snapshot(_ items: [[Representation]], extraTypes: Set<String> = [], app: String? = "com.apple.TextEdit") -> PasteboardSnapshot {
        let types = Set(items.flatMap { $0.map(\.type) }).union(extraTypes)
        return PasteboardSnapshot(items: items, types: types, frontmostBundleID: app, frontmostAppName: app == nil ? nil : "TextEdit")
    }

    func text(_ s: String) -> [[Representation]] { [[Representation(type: PasteboardType.plainText, data: Data(s.utf8))]] }

    func skipReason(_ decision: CaptureDecision) -> SkipReason? {
        if case .skip(let reason) = decision { return reason }
        return nil
    }

    func draft(_ decision: CaptureDecision, file: StaticString = #filePath, line: UInt = #line) throws -> ClipDraft {
        guard case .capture(let draft) = decision else {
            XCTFail("expected capture, got \(decision)", file: file, line: line)
            throw XCTSkip()
        }
        return draft
    }

    func testCapturesPlainText() throws {
        let d = try draft(CapturePolicy.decide(snapshot(text("hello")), settings: settings))
        XCTAssertEqual(d.kind, .text)
        XCTAssertEqual(d.previewText, "hello")
        XCTAssertEqual(d.sourceAppBundleID, "com.apple.TextEdit")
        XCTAssertEqual(d.sourceAppName, "TextEdit")
        XCTAssertFalse(d.isSensitive)
        XCTAssertEqual(d.byteSize, 5)
    }

    func testPaused() {
        settings.isPaused = true
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(text("x")), settings: settings)), .paused)
    }

    func testConcealedMarkersNeverCaptured() {
        for marker in PasteboardType.neverCapture {
            let s = snapshot(text("secret"), extraTypes: [marker])
            XCTAssertEqual(skipReason(CapturePolicy.decide(s, settings: settings)), .concealed, marker)
        }
    }

    func testExcludedApp() {
        let s = snapshot(text("x"), app: "com.1password.1password")
        XCTAssertEqual(skipReason(CapturePolicy.decide(s, settings: settings)), .excludedApp)
    }

    func testEmptyAndUnsupported() {
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot([]), settings: settings)), .empty)
        let unsupported = [[Representation(type: "com.adobe.pdf", data: Data([1]))]]
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(unsupported), settings: settings)), .empty)
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(text("  \n ")), settings: settings)), .empty)
    }

    func testTextSizeLimit() throws {
        let atLimit = String(repeating: "a", count: 2_000_000)
        XCTAssertNoThrow(try draft(CapturePolicy.decide(snapshot(text(atLimit)), settings: settings)))
        let over = String(repeating: "a", count: 2_000_001)
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(text(over)), settings: settings)), .tooLarge)
    }

    func testTextAndRichFlavorsCountTogether() {
        let big = Data(repeating: 0x61, count: 1_200_000)
        let items = [[Representation(type: PasteboardType.plainText, data: big),
                      Representation(type: PasteboardType.rtf, data: big)]]
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(items), settings: settings)), .tooLarge)
    }

    func testImageSizeLimit() {
        let huge = [[Representation(type: PasteboardType.png, data: Data(repeating: 0, count: 10_000_001))]]
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(huge), settings: settings)), .tooLarge)
    }

    func testFileCountLimit() throws {
        func files(_ n: Int) -> [[Representation]] {
            (0..<n).map { [Representation(type: PasteboardType.fileURL, data: Data("file:///tmp/f\($0)".utf8))] }
        }
        XCTAssertEqual(try draft(CapturePolicy.decide(snapshot(files(1_000)), settings: settings)).fileNames.count, 1_000)
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(files(1_001)), settings: settings)), .tooLarge)
    }

    func testDisabledKinds() {
        settings.captureImages = false
        settings.captureFiles = false
        let image = [[Representation(type: PasteboardType.png, data: makeImage(width: 10, height: 10))]]
        let file = [[Representation(type: PasteboardType.fileURL, data: Data("file:///a".utf8))]]
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(image), settings: settings)), .disabledKind)
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(file), settings: settings)), .disabledKind)
    }

    func testSensitiveMaskedByDefault() throws {
        let d = try draft(CapturePolicy.decide(snapshot(text("password = hunter2")), settings: settings))
        XCTAssertTrue(d.isSensitive)
        // The real preview is kept (encrypted at rest) and masked at display/search time,
        // so "Mark as Not Sensitive" can reveal it again.
        XCTAssertEqual(d.previewText, "password = hunter2")
        XCTAssertEqual(d.content.items[0][0].data, Data("password = hunter2".utf8))
    }

    func testSensitiveDontSave() {
        settings.sensitiveHandling = .dontSave
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(text("password = hunter2")), settings: settings)), .sensitive)
    }

    func testNonAllowlistedFlavorsDropped() throws {
        let items = [[Representation(type: PasteboardType.plainText, data: Data("x".utf8)),
                      Representation(type: "com.apple.private.whatever", data: Data([9, 9]))]]
        let d = try draft(CapturePolicy.decide(snapshot(items), settings: settings))
        XCTAssertEqual(d.content.items[0].map(\.type), [PasteboardType.plainText])
    }

    func testTIFFConvertedToPNGWithThumbnail() throws {
        let items = [[Representation(type: PasteboardType.tiff, data: makeImage(width: 600, height: 300, type: .tiff))]]
        let d = try draft(CapturePolicy.decide(snapshot(items), settings: settings))
        XCTAssertEqual(d.kind, .image)
        XCTAssertEqual(d.content.items[0].map(\.type), [PasteboardType.png])
        XCTAssertEqual(d.previewText, "Image 600×300")
        let thumb = try XCTUnwrap(d.thumbnailPNG)
        XCTAssertEqual(Thumbnailer.pixelSize(thumb).map { max($0.width, $0.height) }, 256)
    }

    func testPNGKeptAndTIFFDroppedWhenBothPresent() throws {
        let png = makeImage(width: 20, height: 20)
        let items = [[Representation(type: PasteboardType.png, data: png),
                      Representation(type: PasteboardType.tiff, data: makeImage(width: 20, height: 20, type: .tiff))]]
        let d = try draft(CapturePolicy.decide(snapshot(items), settings: settings))
        XCTAssertEqual(d.content.items[0].map(\.type), [PasteboardType.png])
        XCTAssertEqual(d.canonical, png)
    }

    func testUndecodableImageIsSkipped() {
        let items = [[Representation(type: PasteboardType.png, data: Data("not png".utf8))]]
        XCTAssertEqual(skipReason(CapturePolicy.decide(snapshot(items), settings: settings)), .empty)
    }

    func testMultiItemTextKeepsAllItems() throws {
        let items = [[Representation(type: PasteboardType.plainText, data: Data("one".utf8))],
                     [Representation(type: PasteboardType.plainText, data: Data("two".utf8))]]
        let d = try draft(CapturePolicy.decide(snapshot(items), settings: settings))
        XCTAssertEqual(d.content.items.count, 2)
        XCTAssertEqual(d.previewText, "one")
    }
}

final class CapturePolicyLimitTests: XCTestCase {
    let settings = CaptureSettings(isPaused: false, excludedBundleIDs: [], captureImages: true, captureFiles: true,
                                   sensitiveHandling: .maskAndExpire)

    func snapshot(_ items: [[Representation]]) -> PasteboardSnapshot {
        PasteboardSnapshot(items: items, types: Set(items.flatMap { $0.map(\.type) }), frontmostBundleID: nil, frontmostAppName: nil)
    }

    func testPixelLimitRejectsOverflowAndNonPositiveDimensions() {
        XCTAssertTrue(CapturePolicy.pixelsWithinLimit(width: 10_000, height: 10_000))
        XCTAssertFalse(CapturePolicy.pixelsWithinLimit(width: 10_001, height: 10_000))
        XCTAssertFalse(CapturePolicy.pixelsWithinLimit(width: Int.max, height: Int.max))
        XCTAssertFalse(CapturePolicy.pixelsWithinLimit(width: -1, height: 100))
        XCTAssertFalse(CapturePolicy.pixelsWithinLimit(width: 0, height: 100))
    }

    func testTooManyItemsSkipped() {
        let items = (0...CapturePolicy.maxItems).map { [Representation(type: PasteboardType.plainText, data: Data("\($0)".utf8))] }
        guard case .skip(.tooLarge) = CapturePolicy.decide(snapshot(items), settings: settings) else { return XCTFail("expected tooLarge") }
    }

    func testAggregateImageBytesCapped() {
        let png = Data(repeating: 1, count: 9_000_000) // under the per-image cap
        let items = (0..<12).map { _ in [Representation(type: PasteboardType.png, data: png)] }
        guard case .skip(.tooLarge) = CapturePolicy.decide(snapshot(items), settings: settings) else { return XCTFail("expected tooLarge") }
    }
}

final class CapturePolicyPrecheckTests: XCTestCase {
    let settings = CaptureSettings(isPaused: false, excludedBundleIDs: ["com.bad"], captureImages: true,
                                   captureFiles: true, sensitiveHandling: .maskAndExpire)

    func testPrecheckRejectsWithoutReadingData() {
        var paused = settings
        paused.isPaused = true
        XCTAssertEqual(CapturePolicy.precheck(types: [PasteboardType.plainText], frontmostBundleID: nil, settings: paused), .paused)
        XCTAssertEqual(CapturePolicy.precheck(types: ["org.nspasteboard.ConcealedType", PasteboardType.plainText],
                                              frontmostBundleID: nil, settings: settings), .concealed)
        XCTAssertEqual(CapturePolicy.precheck(types: [PasteboardType.plainText], frontmostBundleID: "com.bad", settings: settings), .excludedApp)
        XCTAssertEqual(CapturePolicy.precheck(types: ["com.adobe.pdf"], frontmostBundleID: nil, settings: settings), .empty)
        XCTAssertNil(CapturePolicy.precheck(types: [PasteboardType.plainText], frontmostBundleID: "com.ok", settings: settings))
    }
}
