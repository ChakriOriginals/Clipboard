import AppKit
import ClipboardCore
import XCTest
@testable import Clipboard

@MainActor
final class PasteboardWriterTests: XCTestCase {
    var pb: NSPasteboard!

    override func setUp() { pb = makeTestPasteboard() }
    override func tearDown() { pb.releaseGlobally() }

    func testWriterRestoresTextAndReturnsChangeCount() {
        let content = ClipContent(items: [[Representation(type: PasteboardType.plainText, data: Data("héllo 👋".utf8)),
                                           Representation(type: PasteboardType.html, data: Data("<b>h</b>".utf8))]])
        let count = PasteboardWriter.write(content, to: pb)
        XCTAssertEqual(count, pb.changeCount)
        XCTAssertEqual(pb.string(forType: .string), "héllo 👋")
        XCTAssertEqual(pb.data(forType: .html), Data("<b>h</b>".utf8))
    }

    func testWriterRestoresMultipleItems() {
        let urls = ["file:///tmp/a.txt", "file:///tmp/b.txt"]
        let content = ClipContent(items: urls.map { [Representation(type: PasteboardType.fileURL, data: Data($0.utf8))] })
        PasteboardWriter.write(content, to: pb)
        XCTAssertEqual(pb.pasteboardItems?.count, 2)
        let read = pb.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(read?.map(\.path), ["/tmp/a.txt", "/tmp/b.txt"])
    }

    func testPNGAlsoProvidesTIFF() {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        PasteboardWriter.write(ClipContent(items: [[Representation(type: PasteboardType.png, data: png)]]), to: pb)
        XCTAssertEqual(pb.data(forType: .png), png)
        XCTAssertNotNil(pb.data(forType: .tiff))
        XCTAssertNotNil(NSImage(pasteboard: pb))
    }

    func testOnlyTheFirstImageOffersTIFF() {
        // TIFF is uncompressed: one lazy conversion per restore, not one per item of a 1,000-item entry.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        let items = (0..<3).map { _ in [Representation(type: PasteboardType.png, data: png)] }
        PasteboardWriter.write(ClipContent(items: items), to: pb)
        let offered = pb.pasteboardItems?.map { $0.types.contains(.tiff) }
        XCTAssertEqual(offered, [true, false, false])
    }

    func testSensitiveRestoreIsMarkedConcealed() {
        let content = ClipContent(items: [[Representation(type: PasteboardType.plainText, data: Data("secret".utf8))]])
        PasteboardWriter.write(content, to: pb, concealed: true)
        XCTAssertEqual(pb.string(forType: .string), "secret")
        XCTAssertNotNil(pb.data(forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")))
    }
}
