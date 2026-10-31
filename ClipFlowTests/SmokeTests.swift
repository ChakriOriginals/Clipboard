import XCTest
@testable import ClipFlow

final class SmokeTests: XCTestCase {
    func testHostAppBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "dev.clipflow.ClipFlow")
    }

    func testAppIsMenuBarOnly() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }
}
