import Carbon.HIToolbox
import XCTest
@testable import ClipFlow

final class ShortcutTests: XCTestCase {
    func testDefaultIsCommandShiftV() {
        XCTAssertEqual(Shortcut.default.keyCode, 9)
        XCTAssertEqual(Shortcut.default.modifierFlags, [.command, .shift])
        XCTAssertEqual(Shortcut.default.displayString, "⇧⌘V")
        XCTAssertTrue(Shortcut.default.isValid)
    }

    func testRequiresCommandOrControl() {
        XCTAssertFalse(Shortcut(keyCode: 9, modifiers: [.option]).isValid)
        XCTAssertFalse(Shortcut(keyCode: 9, modifiers: [.option, .shift]).isValid)
        XCTAssertFalse(Shortcut(keyCode: 9, modifiers: []).isValid)
        XCTAssertTrue(Shortcut(keyCode: 9, modifiers: [.control]).isValid)
        XCTAssertTrue(Shortcut(keyCode: 9, modifiers: [.command, .option]).isValid)
    }

    func testIgnoresNonShortcutModifierBits() {
        let s = Shortcut(keyCode: 9, modifiers: [.command, .capsLock, .function, .numericPad])
        XCTAssertEqual(s.modifierFlags, [.command])
    }

    func testDisplayOrderAndKeys() {
        XCTAssertEqual(Shortcut(keyCode: 9, modifiers: [.command, .control, .option, .shift]).displayString, "⌃⌥⇧⌘V")
        XCTAssertEqual(Shortcut(keyCode: 49, modifiers: [.control]).displayString, "⌃Space")
        XCTAssertEqual(Shortcut(keyCode: 122, modifiers: [.command]).displayString, "⌘F1")
    }

    func testCarbonModifiers() {
        XCTAssertEqual(Shortcut(keyCode: 9, modifiers: [.command, .shift]).carbonModifiers, 256 | 512)
        XCTAssertEqual(Shortcut(keyCode: 9, modifiers: [.control, .option]).carbonModifiers, 4096 | 2048)
    }

    func testCodableRoundTrip() throws {
        let s = Shortcut(keyCode: 40, modifiers: [.control, .command])
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(s)), s)
    }

    func testStandardEditingShortcutsAreReserved() {
        for key in [kVK_ANSI_V, kVK_ANSI_C, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_A, kVK_ANSI_Q, kVK_ANSI_W] {
            XCTAssertFalse(Shortcut(keyCode: UInt32(key), modifiers: [.command]).isValid, "⌘ + \(key)")
        }
        XCTAssertTrue(Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .option]).isValid)
    }
}
