import AppKit
import XCTest
@testable import Clipboard

final class PasteAccessTests: XCTestCase {
    func testAccessStateMapping() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("accessBehavior requires macOS 15.4") }
        XCTAssertEqual(PasteAccessState.from(.alwaysAllow), .allowed)
        XCTAssertEqual(PasteAccessState.from(.default), .mayPrompt)
        XCTAssertEqual(PasteAccessState.from(.ask), .needsAlwaysAllow)
        XCTAssertEqual(PasteAccessState.from(.alwaysDeny), .denied)
    }

    func testOnlyAllowedAndMayPromptRead() {
        XCTAssertTrue(PasteAccessState.allowed.mayReadAutomatically)
        XCTAssertTrue(PasteAccessState.mayPrompt.mayReadAutomatically)
        XCTAssertFalse(PasteAccessState.needsAlwaysAllow.mayReadAutomatically)
        XCTAssertFalse(PasteAccessState.denied.mayReadAutomatically)
    }

    func testNamedPasteboardIsReadable() {
        XCTAssertTrue(PasteAccessState.current(for: makeTestPasteboard()).mayReadAutomatically)
    }
}
