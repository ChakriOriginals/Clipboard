import Carbon.HIToolbox
import XCTest
@testable import ClipFlow

@MainActor
final class HotKeyTests: XCTestCase {
    /// An unlikely combination so the test never collides with the user's shortcuts.
    let unusual = Shortcut(keyCode: UInt32(kVK_F19), modifiers: [.control, .option, .command])

    func testRegisterUnregisterAndReregister() throws {
        var hotKey: HotKey? = try HotKey(shortcut: unusual) {}
        XCTAssertNotNil(hotKey)
        hotKey?.unregister()
        hotKey = nil
        let again = try HotKey(shortcut: unusual) {}
        again.unregister()
    }

    func testInvalidShortcutThrows() {
        XCTAssertThrowsError(try HotKey(shortcut: Shortcut(keyCode: 9, modifiers: [.option])) {}) { error in
            XCTAssertEqual(error as? HotKeyError, .invalidShortcut)
        }
    }

    func testDispatchInvokesMatchingAction() throws {
        var fired = 0
        let hotKey = try HotKey(shortcut: unusual) { fired += 1 }
        HotKey.dispatch(id: hotKey.id)
        HotKey.dispatch(id: hotKey.id &+ 999)
        XCTAssertEqual(fired, 1)
        hotKey.unregister()
        HotKey.dispatch(id: hotKey.id)
        XCTAssertEqual(fired, 1)
    }
}
