import XCTest
@testable import ClipboardCore

final class ThumbnailerTests: XCTestCase {
    func testPixelSize() throws {
        let size = try XCTUnwrap(Thumbnailer.pixelSize(makeImage(width: 300, height: 120)))
        XCTAssertEqual(size.width, 300)
        XCTAssertEqual(size.height, 120)
    }

    func testThumbnailFitsWithin256() throws {
        let thumb = try XCTUnwrap(Thumbnailer.thumbnailPNG(fromImageData: makeImage(width: 1000, height: 400)))
        let size = try XCTUnwrap(Thumbnailer.pixelSize(thumb))
        XCTAssertEqual(max(size.width, size.height), 256)
        XCTAssertEqual(thumb.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testTIFFConvertsToPNG() throws {
        let png = try XCTUnwrap(Thumbnailer.pngData(fromImageData: makeImage(width: 40, height: 30, type: .tiff)))
        XCTAssertEqual(png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(Thumbnailer.pixelSize(png)?.width, 40)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(Thumbnailer.pixelSize(Data("not an image".utf8)))
        XCTAssertNil(Thumbnailer.thumbnailPNG(fromImageData: Data()))
        XCTAssertNil(Thumbnailer.pngData(fromImageData: Data([1, 2, 3])))
    }
}
