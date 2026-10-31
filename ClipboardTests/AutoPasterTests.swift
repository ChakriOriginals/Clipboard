import XCTest
@testable import Clipboard

@MainActor
final class AutoPasterTests: XCTestCase {
    func testDoesNotPostWhenUntrusted() {
        var posted: [CGKeyCode] = []
        let paster = AutoPaster(isTrusted: { false }, post: { posted.append($0) })
        XCTAssertFalse(paster.paste())
        XCTAssertTrue(posted.isEmpty)
    }

    func testPostsOnceWhenTrusted() {
        var posted: [CGKeyCode] = []
        let paster = AutoPaster(isTrusted: { true }, post: { posted.append($0) })
        XCTAssertTrue(paster.paste())
        XCTAssertEqual(posted, [AutoPaster.keyCodeForV()])
    }

    func testKeyCodeForVIsAValidVirtualKey() {
        XCTAssertLessThan(AutoPaster.keyCodeForV(), 128)
    }

    func testDoesNotPasteWhenPasteboardChangedSinceRestore() {
        var posted = 0
        let paster = AutoPaster(isTrusted: { true }, post: { _ in posted += 1 })
        XCTAssertFalse(paster.paste(ifChangeCountIs: 41, current: 42))
        XCTAssertTrue(paster.paste(ifChangeCountIs: 42, current: 42))
        XCTAssertEqual(posted, 1)
    }
}
