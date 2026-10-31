import AppKit
import XCTest
@testable import ClipFlow

final class KeyRouterTests: XCTestCase {
    func route(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = [], _ chars: String? = nil) -> PanelCommand? {
        KeyRouter.command(keyCode: keyCode, modifiers: modifiers, charactersIgnoringModifiers: chars)
    }

    func testNavigationAndSelection() {
        XCTAssertEqual(route(126), .moveUp)
        XCTAssertEqual(route(125), .moveDown)
        XCTAssertEqual(route(36), .select)
        XCTAssertEqual(route(76), .select)
        XCTAssertEqual(route(36, .shift), .copyOnly)
        XCTAssertEqual(route(53), .close)
    }

    func testCommandShortcuts() {
        for n in 1...9 {
            XCTAssertEqual(route(18, .command, "\(n)"), .selectIndex(n - 1))
        }
        XCTAssertEqual(route(35, .command, "p"), .togglePin)
        XCTAssertEqual(route(51, .command, nil), .delete)
    }

    func testTypingIsLeftToSearchField() {
        XCTAssertNil(route(0, [], "a"))
        XCTAssertNil(route(51, [], nil))            // plain backspace edits the query
        XCTAssertNil(route(18, [], "1"))            // digits without ⌘ are typed
        XCTAssertNil(route(0, .command, "a"))       // ⌘A select-all stays with the text field
        XCTAssertNil(route(18, .command, "0"))
    }
}
