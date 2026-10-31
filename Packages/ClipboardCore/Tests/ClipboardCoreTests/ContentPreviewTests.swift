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

    func testTerminalControlCharactersAreShown() {
        // Backspaces, a lone carriage return and ESC are invisible in a label but act in a terminal.
        let text = "ls\u{8}\u{8}rm x\recho ok\u{1B}[201~"
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.plainText, text)]]))
        XCTAssertEqual(p.text, "ls⟨U+8⟩⟨U+8⟩rm x⟨U+D⟩echo ok⟨U+1B⟩[201~")
        XCTAssertTrue(p.hasInvisibleCharacters)
    }

    func testBlankLookingFillersAreShownButEmojiStayIntact() {
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.plainText, "a\u{3164}b \u{2764}\u{FE0F} 👩‍💻")]]))
        XCTAssertEqual(p.text, "a⟨U+3164⟩b \u{2764}\u{FE0F} 👩‍💻")
        XCTAssertTrue(p.hasInvisibleCharacters)
    }

    func testHTMLOnlyTextKeepsInvisibleCharactersVisible() {
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.html, "<p>safe\u{202E}txt.exe\u{200B}</p>")]]))
        XCTAssertEqual(p.text?.trimmingCharacters(in: .whitespaces), "safe⟨U+202E⟩txt.exe⟨U+200B⟩")
        XCTAssertTrue(p.hasInvisibleCharacters)
    }

    func testTabsAndLineBreaksStayReal() {
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.plainText, "a\tb\r\nc\nd")]]))
        XCTAssertEqual(p.text, "a\tb\r\nc\nd")
        XCTAssertEqual(p.lineCount, 3)
        XCTAssertFalse(p.hasInvisibleCharacters)
    }

    func testFileNamesShowInvisibleCharacters() {
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.fileURL, "file:///tmp/invoice%E2%80%AEfdp.exe")]]))
        XCTAssertEqual(p.fileNames, ["invoice⟨U+202E⟩fdp.exe"])
        XCTAssertTrue(p.hasInvisibleCharacters)
    }

    func testTruncationIsReportedWhenMarkersPushTextPastTheLimit() {
        let text = String(repeating: "a", count: ContentPreview.maxCharacters - 5) + "\u{202E}abc"
        let p = ContentPreview.make(from: ClipContent(items: [[rep(PasteboardType.plainText, text)]]))
        XCTAssertTrue(p.isTruncated)
        XCTAssertLessThanOrEqual(p.text?.count ?? 0, ContentPreview.maxCharacters)
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
