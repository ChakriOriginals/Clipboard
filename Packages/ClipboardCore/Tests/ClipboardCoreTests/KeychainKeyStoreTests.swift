import XCTest
@testable import ClipboardCore

final class KeychainKeyStoreTests: XCTestCase {
    var store: KeychainKeyStore!

    override func setUp() {
        store = KeychainKeyStore(service: "dev.clipflow.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        try? store.deleteKey()
    }

    func testLoadMissingReturnsNil() throws {
        XCTAssertNil(try store.loadKey())
    }

    func testCreateLoadDelete() throws {
        let created = try store.createKey()
        let loaded = try XCTUnwrap(try store.loadKey())
        XCTAssertEqual(created.withUnsafeBytes { Data($0) }, loaded.withUnsafeBytes { Data($0) })
        XCTAssertEqual(loaded.bitCount, 256)
        try store.deleteKey()
        XCTAssertNil(try store.loadKey())
    }

    func testDeleteMissingDoesNotThrow() {
        XCTAssertNoThrow(try store.deleteKey())
    }

    func testInMemoryKeyStoreBehavesLikeKeychain() throws {
        let mem = InMemoryKeyStore()
        XCTAssertNil(try mem.loadKey())
        let key = try mem.createKey()
        XCTAssertEqual(try mem.loadKey()?.withUnsafeBytes { Data($0) }, key.withUnsafeBytes { Data($0) })
        try mem.deleteKey()
        XCTAssertNil(try mem.loadKey())
    }
}
