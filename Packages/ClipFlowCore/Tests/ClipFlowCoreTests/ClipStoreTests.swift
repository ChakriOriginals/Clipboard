import XCTest
@testable import ClipFlowCore

final class ClipStoreTests: XCTestCase {
    var dir: URL!
    var keys: InMemoryKeyStore!
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        dir = makeTempDirectory()
        keys = InMemoryKeyStore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeStore(keyStore: KeyStore? = nil) async throws -> ClipStore {
        let store = ClipStore(directory: dir, keyStore: keyStore ?? keys, deviceID: "device-1")
        _ = try await store.open()
        return store
    }

    var dbURL: URL { dir.appendingPathComponent("history.sqlite") }

    func testInsertAndReload() async throws {
        let store = try await makeStore()
        let item = try await store.insertOrBump(textDraft("hello café 👋"), now: now)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.deviceID, "device-1")

        let reopened = try await makeStore()
        let (items, purged) = try await reopened.allItems()
        XCTAssertEqual(purged, 0)
        XCTAssertEqual(items.map(\.id), [item.id])
        XCTAssertEqual(items[0].summary.previewText, "hello café 👋")
        XCTAssertEqual(items[0].summary.sourceAppName, "TextEdit")
        XCTAssertEqual(items[0].createdAt, now)
        let content = try await reopened.content(id: item.id)
        XCTAssertEqual(content.items[0][0].data, Data("hello café 👋".utf8))
    }

    func testDuplicateBumpsInsteadOfInserting() async throws {
        let store = try await makeStore()
        let first = try await store.insertOrBump(textDraft("same"), now: now)
        let later = now.addingTimeInterval(60)
        let second = try await store.insertOrBump(textDraft("same"), now: later)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.lastCopiedAt, later)
        XCTAssertEqual(second.createdAt, now)
        let items = try await store.allItems().items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].lastCopiedAt, later)
    }

    func testItemsOrderedByLastCopiedDescending() async throws {
        let store = try await makeStore()
        let a = try await store.insertOrBump(textDraft("a"), now: now)
        let b = try await store.insertOrBump(textDraft("b"), now: now.addingTimeInterval(1))
        try await store.bump(id: a.id, now: now.addingTimeInterval(2))
        let v1 = try await store.allItems().items.map(\.id)
        XCTAssertEqual(v1, [a.id, b.id])
    }

    func testRawFileContainsNoPlaintext() async throws {
        let store = try await makeStore()
        _ = try await store.insertOrBump(textDraft("hunter2-secret-marker"), now: now)
        let bytes = try Data(contentsOf: dbURL)
        XCTAssertNil(bytes.range(of: Data("hunter2-secret-marker".utf8)))
        XCTAssertNil(bytes.range(of: Data("TextEdit".utf8)))
    }

    func testTamperedRowIsSkippedAndPurged() async throws {
        let store = try await makeStore()
        let good = try await store.insertOrBump(textDraft("good"), now: now)
        let bad = try await store.insertOrBump(textDraft("bad"), now: now.addingTimeInterval(1))
        let raw = try SQLiteDatabase(path: dbURL.path)
        var blob = Data()
        try raw.query("SELECT summary FROM clips WHERE id = ?", [.text(bad.id.uuidString)]) { blob = $0.blob(0) }
        blob[blob.count - 1] ^= 0xFF
        try raw.run("UPDATE clips SET summary = ? WHERE id = ?", [.blob(blob), .text(bad.id.uuidString)])

        let (items, purged) = try await store.allItems()
        XCTAssertEqual(items.map(\.id), [good.id])
        XCTAssertEqual(purged, 1)
        let again = try await store.allItems()
        XCTAssertEqual(again.purgedCorrupt, 0)
        XCTAssertEqual(again.items.count, 1)
    }

    func testMissingKeyMovesDatabaseAside() async throws {
        let store = try await makeStore()
        _ = try await store.insertOrBump(textDraft("old"), now: now)

        let fresh = ClipStore(directory: dir, keyStore: InMemoryKeyStore(), deviceID: "device-1")
        let result = try await fresh.open()
        guard case .recoveredFromUnreadable(let movedTo) = result else { return XCTFail("expected recovery, got \(result)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedTo.path))
        XCTAssertTrue(movedTo.lastPathComponent.hasPrefix("history.unreadable-"))
        let v2 = try await fresh.allItems().items.count
        XCTAssertEqual(v2, 0)
    }

    func testWrongKeyMovesDatabaseAside() async throws {
        let store = try await makeStore()
        _ = try await store.insertOrBump(textDraft("old"), now: now)
        let otherKeys = InMemoryKeyStore()
        _ = try otherKeys.createKey()
        let fresh = ClipStore(directory: dir, keyStore: otherKeys, deviceID: "d")
        guard case .recoveredFromUnreadable = try await fresh.open() else { return XCTFail("expected recovery") }
        let v3 = try await fresh.allItems().items.count
        XCTAssertEqual(v3, 0)
    }

    func testGarbageDatabaseFileIsMovedAside() async throws {
        _ = try keys.createKey()
        try Data("this is not a database".utf8).write(to: dbURL)
        let store = ClipStore(directory: dir, keyStore: keys, deviceID: "d")
        guard case .recoveredFromUnreadable = try await store.open() else { return XCTFail("expected recovery") }
        _ = try await store.insertOrBump(textDraft("works"), now: now)
        let v4 = try await store.allItems().items.count
        XCTAssertEqual(v4, 1)
    }

    func testUnreadableKeyThrowsLockedAndLeavesFileUntouched() async throws {
        let store = try await makeStore()
        _ = try await store.insertOrBump(textDraft("precious"), now: now)
        let before = try Data(contentsOf: dbURL)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()

        let locked = ClipStore(directory: dir, keyStore: UnreadableKeyStore(status: -25293), deviceID: "d")
        do {
            _ = try await locked.open()
            XCTFail("expected locked")
        } catch ClipStoreError.locked(let status) {
            XCTAssertEqual(status, -25293)
        }
        XCTAssertEqual(try Data(contentsOf: dbURL), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), files)
    }

    func testPinDeleteClearUnpinned() async throws {
        let store = try await makeStore()
        let a = try await store.insertOrBump(textDraft("a"), now: now)
        let b = try await store.insertOrBump(textDraft("b"), now: now)
        let c = try await store.insertOrBump(textDraft("c"), now: now)
        try await store.setPinned(a.id, true)
        try await store.setSensitive(b.id, true)
        var items = try await store.allItems().items
        XCTAssertEqual(items.first { $0.id == a.id }?.isPinned, true)
        XCTAssertEqual(items.first { $0.id == b.id }?.isSensitive, true)

        try await store.delete(ids: [c.id])
        let v5 = try await store.allItems().items.map(\.id)
        XCTAssertEqual(Set(v5), [a.id, b.id])

        try await store.clearUnpinned()
        items = try await store.allItems().items
        XCTAssertEqual(items.map(\.id), [a.id])
    }

    func testDestroyEverythingDeletesFileAndKey() async throws {
        let store = try await makeStore()
        _ = try await store.insertOrBump(textDraft("bye"), now: now)
        let oldKey = try XCTUnwrap(try keys.loadKey()).withUnsafeBytes { Data($0) }
        try await store.destroyEverything()
        let v6 = try await store.allItems().items.count
        XCTAssertEqual(v6, 0)
        let newKey = try XCTUnwrap(try keys.loadKey()).withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(oldKey, newKey)
        _ = try await store.insertOrBump(textDraft("hello again"), now: now)
        let v7 = try await store.allItems().items.count
        XCTAssertEqual(v7, 1)
    }

    func testFilePermissions() async throws {
        let store = try await makeStore()
        _ = try await store.insertOrBump(textDraft("x"), now: now)
        let dirPerms = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        let filePerms = try FileManager.default.attributesOfItem(atPath: dbURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(dirPerms, 0o700)
        XCTAssertEqual(filePerms, 0o600)
        XCTAssertEqual(try dir.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testThumbnailStoredSeparately() async throws {
        let store = try await makeStore()
        var draft = textDraft("img")
        draft = ClipDraft(kind: .image, previewText: "Image 10×10", sourceAppBundleID: nil, sourceAppName: nil,
                          fileNames: [], isSensitive: false, content: draft.content, canonical: Data("png".utf8),
                          thumbnailPNG: Data([0x89, 0x50, 0x4E, 0x47]), byteSize: 4)
        let item = try await store.insertOrBump(draft, now: now)
        XCTAssertTrue(item.hasThumbnail)
        let v8 = try await store.thumbnail(id: item.id)
        XCTAssertEqual(v8, Data([0x89, 0x50, 0x4E, 0x47]))
        let plain = try await store.insertOrBump(textDraft("no thumb"), now: now)
        XCTAssertFalse(plain.hasThumbnail)
        let none = try await store.thumbnail(id: plain.id)
        XCTAssertNil(none)
    }

    func testMultiItemContentRoundTrips() async throws {
        let store = try await makeStore()
        let urls = ["file:///a.txt", "file:///b.txt"].map { Representation(type: "public.file-url", data: Data($0.utf8)) }
        let draft = ClipDraft(kind: .file, previewText: "a.txt, b.txt", sourceAppBundleID: nil, sourceAppName: nil,
                              fileNames: ["a.txt", "b.txt"], isSensitive: false,
                              content: ClipContent(items: urls.map { [$0] }), canonical: Data("a\nb".utf8),
                              thumbnailPNG: nil, byteSize: 26)
        let item = try await store.insertOrBump(draft, now: now)
        let content = try await store.content(id: item.id)
        XCTAssertEqual(content.items.count, 2)
        XCTAssertEqual(content.items[1][0].data, Data("file:///b.txt".utf8))
        let v9 = try await store.allItems().items[0].summary.fileNames
        XCTAssertEqual(v9, ["a.txt", "b.txt"])
    }

    func testOperationsBeforeOpenThrow() async {
        let store = ClipStore(directory: dir, keyStore: keys, deviceID: "d")
        do {
            _ = try await store.allItems()
            XCTFail("expected notOpen")
        } catch {
            XCTAssertEqual(error as? ClipStoreError, .notOpen)
        }
    }

    func testNewerSchemaIsRefusedAndLeftUntouched() async throws {
        let store = try await makeStore()
        _ = try await store.insertOrBump(textDraft("future"), now: now)
        let raw = try SQLiteDatabase(path: dbURL.path)
        try raw.setUserVersion(99)
        raw.close()
        let before = try Data(contentsOf: dbURL)
        let reopened = ClipStore(directory: dir, keyStore: keys, deviceID: "d")
        do {
            _ = try await reopened.open()
            XCTFail("expected newerVersion")
        } catch {
            XCTAssertEqual(error as? ClipStoreError, .newerVersion)
        }
        XCTAssertEqual(try Data(contentsOf: dbURL), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("unreadable") }, [])
    }

    func testUnknownKindIsSkippedButNotDeleted() async throws {
        let store = try await makeStore()
        let item = try await store.insertOrBump(textDraft("from the future"), now: now)
        let raw = try SQLiteDatabase(path: dbURL.path)
        try raw.run("UPDATE clips SET kind = 'hologram' WHERE id = ?", [.text(item.id.uuidString)])
        let (items, purged) = try await store.allItems()
        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(purged, 0)
        var count = 0
        try raw.query("SELECT COUNT(*) FROM clips", []) { count = Int($0.int(0)) }
        XCTAssertEqual(count, 1)
    }

    func testBusyDatabaseIsNotMovedAside() async throws {
        let store = try await makeStore()
        _ = try await store.insertOrBump(textDraft("live"), now: now)
        let locker = try SQLiteDatabase(path: dbURL.path)
        try locker.execute("BEGIN EXCLUSIVE")
        let second = ClipStore(directory: dir, keyStore: keys, deviceID: "d", busyTimeoutMilliseconds: 50)
        do {
            _ = try await second.open()
            XCTFail("expected an error while the database is locked")
        } catch {
            XCTAssertNotEqual(error as? ClipStoreError, .locked(errSecDecode))
        }
        try locker.execute("ROLLBACK")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("unreadable") }, [])
        let items = try await store.allItems().items
        XCTAssertEqual(items.count, 1)
    }

    func testDestroyEverythingRemovesMovedAsideCopies() async throws {
        let store = try await makeStore()
        _ = try await store.insertOrBump(textDraft("old"), now: now)
        let fresh = ClipStore(directory: dir, keyStore: InMemoryKeyStore(), deviceID: "d")
        _ = try await fresh.open()
        try await fresh.destroyEverything()
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("history") }
        XCTAssertEqual(leftovers, ["history.sqlite"])
    }
}
