import XCTest
@testable import ClipboardCore

final class SmokeTests: XCTestCase {
    func testSchemaVersion() {
        XCTAssertEqual(ClipboardCore.schemaVersion, 1)
    }
}
