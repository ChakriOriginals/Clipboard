import XCTest
@testable import ClipboardCore

final class ContentPreviewTests: XCTestCase {
    func rep(_ type: String, _ s: String) -> Representation { Representation(type: type, data: Data(s.utf8)) }

    func testPlainTextKeepsRealLineBreaks() {
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.plainText, "one\ntwo\n  three")]]))
        XCTAssertEqual(p.text, "one\ntwo\n  three")
        XCTAssertEqual(p.lineCount, 3)
        XCTAssertFalse(p.isTruncated)
        XCTAssertEqual(p.flavors, ["Plain Text"])
        XCTAssertEqual(p.itemCount, 1)
    }

    func testNamesEveryFlavorThatWillBePasted() {
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.html, "<b>x</b>"), rep(PasteboardType.plainText, "x"),
                                                                rep(PasteboardType.rtf, "{\\rtf1 x}")]]))
        XCTAssertEqual(p.flavors, ["Plain Text", "Rich Text", "HTML"])
        XCTAssertEqual(p.text, "x")
    }

    func testHTMLOnlyFallsBackToStrippedText() {
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.html, "<p>Hello <b>there</b></p>")]]))
        XCTAssertEqual(p.text, "Hello there")
    }

    func testFilesListEveryItem() {
        let items = ["file:///tmp/a.txt", "file:///tmp/My%20Doc.pdf"].map { [rep(PasteboardType.fileURL, $0)] }
        let p = ContentPreview.make(from: ClipContent(items: items))
        XCTAssertEqual(p.fileNames, ["a.txt", "My Doc.pdf"])
        XCTAssertEqual(p.itemCount, 2)
        XCTAssertEqual(p.flavors, ["Files"])
        XCTAssertNil(p.text)
    }

    func testImageKeepsPNGAndTextBesideIt() {
        let png = Representation(type: PasteboardType.png, data: Data([0x89, 0x50]))
        let p = ContentPreview.make(from: ClipContent(items: [[png, rep(PasteboardType.plainText, "caption")]]))
        XCTAssertEqual(p.imagePNG, Data([0x89, 0x50]))
        XCTAssertEqual(p.flavors, ["Plain Text", "Image"])
    }

    func testInvisibleControlsAreShownNotHidden() {
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.plainText, "safe\u{202E}txt.exe\u{200B}")]]))
        XCTAssertEqual(p.text, "safe⟨U+202E⟩txt.exe⟨U+200B⟩")
        XCTAssertTrue(p.hasInvisibleCharacters)
    }

    func testLongTextIsTruncatedForDisplay() {
        let long = String(repeating: "a", count: ContentPreview.maxCharacters + 10)
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.plainText, long)]]))
        XCTAssertEqual(p.text?.count, ContentPreview.maxCharacters)
        XCTAssertTrue(p.isTruncated)
    }

    func testLaterItemsAreCounted() {
        let items = [[rep(PasteboardType.plainText, "first")], [rep(PasteboardType.plainText, "second")]]
        let p = ContentPreview.make(from: ClipContent(items: items))
        XCTAssertEqual(p.itemCount, 2)
        XCTAssertEqual(p.text, "first")
    }
}
