import XCTest
@testable import ClipFlow

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
}
