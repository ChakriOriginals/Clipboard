import XCTest
@testable import ClipboardCore

final class ContentClassifierTests: XCTestCase {
    func rep(_ type: String, _ string: String) -> Representation { Representation(type: type, data: Data(string.utf8)) }
    func plain(_ s: String) -> [[Representation]] { [[rep(PasteboardType.plainText, s)]] }

    func testPlainText() throws {
        let c = try XCTUnwrap(ContentClassifier.classify(plain("Hello, world")))
        XCTAssertEqual(c.kind, .text)
        XCTAssertEqual(c.previewText, "Hello, world")
        XCTAssertEqual(c.canonical, Data("Hello, world".utf8))
    }

    func testURL() throws {
        XCTAssertEqual(ContentClassifier.classify(plain("  https://example.com/a?b=1 \n"))?.kind, .url)
        XCTAssertEqual(ContentClassifier.classify(plain("see https://x.com"))?.kind, .text)
        XCTAssertEqual(ContentClassifier.classify(plain("javascript:alert(1)"))?.kind, .text)
    }

    func testURLFlavorWithoutPlainText() throws {
        let c = try XCTUnwrap(ContentClassifier.classify([[rep(PasteboardType.url, "https://apple.com")]]))
        XCTAssertEqual(c.kind, .url)
        XCTAssertEqual(c.previewText, "https://apple.com")
    }

    func testCodeSnippets() {
        let swift = "func greet(name: String) -> String {\n    return \"Hello, \\(name)\"\n}"
        let js = "const add = (a, b) => {\n  console.log(a);\n  return a + b;\n};"
        let python = "def add(a, b):\n    return a + b\n"
        for snippet in [swift, js, python] {
            XCTAssertEqual(ContentClassifier.classify(plain(snippet))?.kind, .code, snippet)
        }
    }

    func testProseIsNotCode() {
        XCTAssertEqual(ContentClassifier.classify(plain("The quick brown fox jumps over the lazy dog."))?.kind, .text)
        let paragraph = "I went for a walk today.\nIf it rains, I stay home.\nThen I return to work."
        XCTAssertEqual(ContentClassifier.classify(plain(paragraph))?.kind, .text)
    }

    func testRichTextUsesPlainForPreview() throws {
        let c = try XCTUnwrap(ContentClassifier.classify([[rep(PasteboardType.rtf, "{\\rtf1 Bold}"),
                                                           rep(PasteboardType.plainText, "Bold")]]))
        XCTAssertEqual(c.kind, .richText)
        XCTAssertEqual(c.previewText, "Bold")
    }

    func testHTMLOnlyIsStrippedForPreview() throws {
        let html = "<html><head><style>p{}</style><script>alert(1)</script></head><body><p>Hi &amp; <b>bye</b></p></body></html>"
        let c = try XCTUnwrap(ContentClassifier.classify([[rep(PasteboardType.html, html)]]))
        XCTAssertEqual(c.kind, .richText)
        XCTAssertEqual(c.previewText, "Hi & bye")
    }

    func testStripTagsIsLinearOnUnterminatedInput() {
        // Doubling the input must roughly double the time (a backtracking regex quadruples it).
        func time(_ s: String) -> TimeInterval {
            let start = DispatchTime.now()
            _ = ContentClassifier.stripTags(s)
            return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        }
        for unit in ["<", "<script>", "<a "] {
            let small = String(repeating: unit, count: 100_000 / unit.count)
            let large = String(repeating: unit, count: 400_000 / unit.count)
            _ = time(small) // warm up
            let ratio = time(large) / max(time(small), 1e-4)
            XCTAssertLessThan(ratio, 8, "4x input took \(ratio)x time for unit \(unit)")
        }
    }

    func testStripTagsHandlesNestedAndCaseInsensitiveBlocks() {
        XCTAssertEqual(ContentClassifier.stripTags("<SCRIPT type=x>a<b>c</SCRIPT >Keep<br/>this &lt;ok&gt;"), "Keep this <ok>")
        XCTAssertEqual(ContentClassifier.stripTags("a < b and c > d"), "a < b and c > d")
    }

    func testFiles() throws {
        let items = ["file:///Users/me/a.txt", "file:///Users/me/My%20Doc.pdf", "file:///tmp/c"].map {
            [rep(PasteboardType.fileURL, $0)]
        }
        let c = try XCTUnwrap(ContentClassifier.classify(items))
        XCTAssertEqual(c.kind, .file)
        XCTAssertEqual(c.fileNames, ["a.txt", "My Doc.pdf", "c"])
        XCTAssertEqual(c.previewText, "a.txt, My Doc.pdf, c")
    }

    func testNonFileURLInFileFlavorIsIgnored() {
        XCTAssertNil(ContentClassifier.classify([[rep(PasteboardType.fileURL, "https://evil.example/x")]]))
    }

    func testKindPriority() throws {
        let png = Representation(type: PasteboardType.png, data: Data([0x89, 0x50]))
        let file = rep(PasteboardType.fileURL, "file:///a.png")
        XCTAssertEqual(ContentClassifier.classify([[png, file, rep(PasteboardType.plainText, "a.png")]])?.kind, .file)
        XCTAssertEqual(ContentClassifier.classify([[png, rep(PasteboardType.plainText, "https://a.com")]])?.kind, .image)
        XCTAssertEqual(ContentClassifier.classify([[rep(PasteboardType.html, "<a>x</a>"),
                                                    rep(PasteboardType.plainText, "https://a.com")]])?.kind, .url)
        let code = "if (x) {\n  y();\n  z();\n}"
        XCTAssertEqual(ContentClassifier.classify([[rep(PasteboardType.rtf, "{\\rtf1}"),
                                                    rep(PasteboardType.plainText, code)]])?.kind, .code)
    }

    func testImageCanonicalIsPNGBytes() throws {
        let png = Representation(type: PasteboardType.png, data: Data([1, 2, 3]))
        let c = try XCTUnwrap(ContentClassifier.classify([[png]]))
        XCTAssertEqual(c.kind, .image)
        XCTAssertEqual(c.canonical, Data([1, 2, 3]))
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(ContentClassifier.classify([]))
        XCTAssertNil(ContentClassifier.classify([[]]))
        XCTAssertNil(ContentClassifier.classify(plain("   \n\t ")))
        XCTAssertNil(ContentClassifier.classify([[Representation(type: PasteboardType.plainText, data: Data([0xFF, 0xFE, 0xFD]))]]))
    }

    func testPreviewCollapsesWhitespace() {
        XCTAssertEqual(ContentClassifier.preview("  a\n\n b\t\tc  "), "a ⏎ b c")
    }

    func testPreviewDoesNotSplitEmoji() {
        let family = "👨‍👩‍👧"
        let preview = ContentClassifier.preview(String(repeating: family, count: 20), limit: 5)
        XCTAssertEqual(preview, String(repeating: family, count: 5) + "…")
    }

    func testUnicodeCanonicalPreservesExactBytes() throws {
        let c = try XCTUnwrap(ContentClassifier.classify(plain("café ☕️ 日本語")))
        XCTAssertEqual(String(data: c.canonical, encoding: .utf8), "café ☕️ 日本語")
    }

    func testOpenableURL() {
        XCTAssertEqual(ContentClassifier.openableURL(" https://example.com/path ")?.absoluteString, "https://example.com/path")
        XCTAssertNotNil(ContentClassifier.openableURL("http://localhost:8080"))
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "ftp://x.com", "http://", "https://a.com b", "",
                    "x-apple.systempreferences:com.apple"] {
            XCTAssertNil(ContentClassifier.openableURL(bad), bad)
        }
    }

    func testPreviewMarksLineBreaksAndDropsInvisibleControls() {
        XCTAssertEqual(ContentClassifier.preview("ls\nrm -rf ~"), "ls ⏎ rm -rf ~")
        XCTAssertEqual(ContentClassifier.preview("safe\u{202E}txt.exe\u{200B}"), "safetxt.exe")
    }
}
