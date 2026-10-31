import AppKit
import ClipFlowCore
import XCTest
@testable import ClipFlow

@MainActor
final class PasteboardMonitorTests: XCTestCase {
    var pb: NSPasteboard!
    var snapshots: [PasteboardSnapshot] = []
    var skips: [SkipReason] = []
    var settings = enabledCapture
    var access = PasteAccessState.allowed
    var monitor: PasteboardMonitor!

    override func setUp() {
        pb = makeTestPasteboard()
        snapshots = []
        skips = []
        settings = enabledCapture
        access = .allowed
        monitor = PasteboardMonitor(pasteboard: pb, settings: { [unowned self] in settings },
                                    accessState: { [unowned self] in access },
                                    frontmostApp: { (bundleID: "com.apple.TextEdit", name: "TextEdit") },
                                    onSnapshot: { [unowned self] in snapshots.append($0) },
                                    onSkip: { [unowned self] in skips.append($0) })
        monitor.start()
    }

    override func tearDown() {
        monitor.stop()
        pb.releaseGlobally()
    }

    func copy(_ string: String) {
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    func plainText(_ snapshot: PasteboardSnapshot?) -> String? {
        snapshot?.items.first?.first { $0.type == PasteboardType.plainText }.flatMap { String(data: $0.data, encoding: .utf8) }
    }

    func testExistingContentAtStartIsNotCaptured() {
        monitor.pollNow()
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testPollCapturesTextOnChange() {
        copy("hello")
        monitor.pollNow()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(plainText(snapshots.first), "hello")
        XCTAssertEqual(snapshots.first?.frontmostBundleID, "com.apple.TextEdit")
    }

    func testNoChangeNoCallback() {
        copy("hello")
        monitor.pollNow()
        monitor.pollNow()
        monitor.pollNow()
        XCTAssertEqual(snapshots.count, 1)
    }

    func testTwoWritesBetweenPollsCapturesLatestOnly() {
        copy("first")
        copy("second")
        monitor.pollNow()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(plainText(snapshots.first), "second")
    }

    func testWriterChangeIgnoredButNextExternalChangeCaptured() {
        let content = ClipContent(items: [[Representation(type: PasteboardType.plainText, data: Data("restored".utf8))]])
        monitor.ignore(changeCount: PasteboardWriter.write(content, to: pb))
        monitor.pollNow()
        XCTAssertTrue(snapshots.isEmpty)
        copy("external")
        monitor.pollNow()
        XCTAssertEqual(plainText(snapshots.last), "external")
    }

    func testPausedSkipsWithoutReading() {
        settings.isPaused = true
        copy("secret")
        monitor.pollNow()
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertEqual(skips, [.paused])
    }

    func testConcealedSkipsWithoutReading() {
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("p@ssw0rd", forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.writeObjects([item])
        monitor.pollNow()
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertEqual(skips, [.concealed])
    }

    func testNoReadWhenAccessNeedsAlwaysAllow() {
        access = .needsAlwaysAllow
        copy("x")
        monitor.pollNow()
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testRTFOnlyGetsDerivedPlainText() throws {
        let rtf = try NSAttributedString(string: "Bold words").data(from: NSRange(location: 0, length: 10),
                                                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pb.clearContents()
        pb.setData(rtf, forType: .rtf)
        monitor.pollNow()
        XCTAssertEqual(plainText(snapshots.first), "Bold words")
        XCTAssertNotNil(snapshots.first?.items.first?.first { $0.type == PasteboardType.rtf })
    }

    func testOnlyAllowlistedFlavorsAreRead() {
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("x", forType: .string)
        item.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.private"))
        pb.writeObjects([item])
        monitor.pollNow()
        XCTAssertEqual(snapshots.first?.items.first?.map(\.type), [PasteboardType.plainText])
        XCTAssertTrue(snapshots.first?.types.contains("com.example.private") ?? false)
    }

    func testTimerPollsAutomatically() {
        let exp = expectation(description: "captured by timer")
        monitor.stop()
        monitor = PasteboardMonitor(pasteboard: pb, interval: 0.05, settings: { enabledCapture }, accessState: { .allowed },
                                    frontmostApp: { nil }, onSnapshot: { _ in exp.fulfill() }, onSkip: { _ in })
        monitor.start()
        copy("tick")
        wait(for: [exp], timeout: 2)
    }
}
