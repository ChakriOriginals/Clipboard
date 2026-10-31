import XCTest
@testable import ClipFlowCore

final class SmokeTests: XCTestCase {
    func testSchemaVersion() {
        XCTAssertEqual(ClipFlowCore.schemaVersion, 1)
    }
}
