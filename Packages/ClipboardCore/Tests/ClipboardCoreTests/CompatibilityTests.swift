import CryptoKit
import XCTest
@testable import ClipboardCore

/// History written by released versions must keep opening. The fixture was written by the real 0.1.0
/// code (commit 94003e4) with a fixed test key; it must open as-is, never be moved aside.
final class CompatibilityTests: XCTestCase {
    func testOpensHistoryWrittenByVersion010() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/v0.1.0-history", withExtension: "sqlite"))
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.copyItem(at: fixture, to: dir.appendingPathComponent("history.sqlite"))
        let keys = InMemoryKeyStore(key: SymmetricKey(data: Data(repeating: 0x42, count: 32)))
        let store = ClipStore(directory: dir, keyStore: keys, deviceID: "d")

        let result = try await store.open()
        XCTAssertEqual(result, .opened)
        let items = try await store.allItems().items
        XCTAssertEqual(items.map(\.summary.previewText), ["legacy item from 0.1.0"])
        let item = try XCTUnwrap(items.first)
        let content = try await store.content(id: item.id)
        XCTAssertEqual(content.items[0][0].data, Data("legacy item from 0.1.0".utf8))
    }
}
