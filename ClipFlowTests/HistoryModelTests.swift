import CryptoKit
import AppKit
import ClipFlowCore
import XCTest
@testable import ClipFlow

@MainActor
final class HistoryModelTests: XCTestCase {
    var dir: URL!
    var defaults: UserDefaults!
    var suite: String!
    var settings: SettingsStore!
    var keys: InMemoryKeyStore!
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var pb: NSPasteboard!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipFlowAppTests-\(UUID().uuidString)")
        (defaults, suite) = makeTestDefaults()
        settings = SettingsStore(defaults: defaults)
        keys = InMemoryKeyStore()
        pb = makeTestPasteboard()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suite)
        pb.releaseGlobally()
    }

    func makeModel(keyStore: KeyStore? = nil) async -> HistoryModel {
        let store = ClipStore(directory: dir, keyStore: keyStore ?? keys, deviceID: settings.deviceID)
        let model = HistoryModel(store: store, settings: settings, now: { [unowned self] in clock })
        await model.load()
        return model
    }

    func text(_ s: String) -> PasteboardSnapshot {
        PasteboardSnapshot(items: [[Representation(type: PasteboardType.plainText, data: Data(s.utf8))]],
                           types: [PasteboardType.plainText], frontmostBundleID: "com.apple.TextEdit", frontmostAppName: "TextEdit")
    }

    func ingest(_ model: HistoryModel, _ strings: String...) async {
        for s in strings {
            clock += 1
            await model.ingest(text(s))
        }
    }

    func previews(_ model: HistoryModel) -> [String] { model.results.map(\.summary.previewText) }

    func testIngestPutsNewestFirstAndSelectsIt() async {
        let model = await makeModel()
        XCTAssertEqual(model.status, .ready)
        await ingest(model, "one", "two")
        XCTAssertEqual(previews(model), ["two", "one"])
        model.resetForPresentation()
        XCTAssertEqual(model.selectedID, model.results.first?.id)
    }

    func testDuplicateIngestKeepsOneItemAndMovesItUp() async {
        let model = await makeModel()
        await ingest(model, "a", "b", "a")
        XCTAssertEqual(previews(model), ["a", "b"])
        XCTAssertEqual(model.items.count, 2)
    }

    func testPausedIngestsNothing() async {
        let model = await makeModel()
        settings.isPaused = true
        await ingest(model, "secret")
        XCTAssertTrue(model.items.isEmpty)
    }

    func testHistorySurvivesRestart() async {
        let first = await makeModel()
        await ingest(first, "persist me")
        let second = await makeModel()
        XCTAssertEqual(previews(second), ["persist me"])
    }

    func testQueryFiltersResults() async {
        let model = await makeModel()
        await ingest(model, "apple pie", "banana", "https://apple.com")
        model.query.text = "apple"
        XCTAssertEqual(Set(previews(model)), ["apple pie", "https://apple.com"])
        model.query.kind = .urls
        XCTAssertEqual(previews(model), ["https://apple.com"])
        model.query = SearchQuery()
        XCTAssertEqual(model.results.count, 3)
    }

    func testDeleteSelectedKeepsSelectionInBounds() async {
        let model = await makeModel()
        await ingest(model, "c", "b", "a") // results: a, b, c
        model.query.text = ""
        model.selectedID = model.results.last?.id
        await model.delete(model.selectedID!)
        XCTAssertEqual(previews(model), ["a", "b"])
        XCTAssertEqual(model.selectedID, model.results.last?.id)

        model.selectedID = model.results.first?.id
        await model.delete(model.selectedID!)
        XCTAssertEqual(model.selectedID, model.results.first?.id)
        await model.delete(model.selectedID!)
        XCTAssertNil(model.selectedID)
        XCTAssertTrue(model.results.isEmpty)
    }

    func testDeleteWhileFilteredDoesNotCrash() async {
        let model = await makeModel()
        await ingest(model, "match 1", "other", "match 2")
        model.query.text = "match"
        let target = model.results[0].id
        model.selectedID = target
        await model.delete(target)
        XCTAssertEqual(previews(model), ["match 1"])
        XCTAssertEqual(model.selectedID, model.results.first?.id)
    }

    func testMoveSelectionClamps() async {
        let model = await makeModel()
        await ingest(model, "3", "2", "1")
        model.resetForPresentation()
        model.moveSelection(-1)
        XCTAssertEqual(model.selectedID, model.results[0].id)
        model.moveSelection(1)
        model.moveSelection(1)
        model.moveSelection(1)
        XCTAssertEqual(model.selectedID, model.results[2].id)
    }

    func testPinMovesToTopAndSurvivesClearUnpinned() async {
        let model = await makeModel()
        await ingest(model, "keep", "drop")
        let keep = model.results.first { $0.summary.previewText == "keep" }!.id
        await model.togglePin(keep)
        XCTAssertEqual(previews(model), ["keep", "drop"])
        XCTAssertTrue(model.results[0].isPinned)
        await model.clearUnpinned()
        XCTAssertEqual(previews(model), ["keep"])
    }

    func testRestoreWritesContentAndBumpsWithoutDuplicate() async {
        let model = await makeModel()
        await ingest(model, "old", "new")
        let old = model.results.first { $0.summary.previewText == "old" }!.id
        clock += 10
        let changeCount = await model.restore(id: old, to: pb)
        XCTAssertEqual(changeCount, pb.changeCount)
        XCTAssertEqual(pb.string(forType: .string), "old")
        XCTAssertEqual(previews(model), ["old", "new"])
        XCTAssertEqual(model.items.count, 2)
    }

    func testRetentionRemovesOldUnpinned() async {
        let model = await makeModel()
        await ingest(model, "ancient", "pinned")
        await model.togglePin(model.results.first { $0.summary.previewText == "pinned" }!.id)
        clock += 31 * 86_400
        await model.applyRetention()
        XCTAssertEqual(previews(model), ["pinned"])
    }

    func testMaxItemsTrimsOnIngest() async {
        settings.maxItems = 2
        let model = await makeModel()
        await ingest(model, "1", "2", "3")
        XCTAssertEqual(previews(model), ["3", "2"])
    }

    func testToggleSensitive() async {
        let model = await makeModel()
        await ingest(model, "plain")
        let id = model.results[0].id
        await model.toggleSensitive(id)
        XCTAssertTrue(model.results[0].isSensitive)
        await model.toggleSensitive(id)
        XCTAssertFalse(model.results[0].isSensitive)
    }

    func testClearEverythingEmptiesHistory() async {
        let model = await makeModel()
        await ingest(model, "x")
        await model.clearEverything()
        XCTAssertTrue(model.items.isEmpty)
        await ingest(model, "after")
        XCTAssertEqual(previews(model), ["after"])
    }

    func testLockedKeyStoreBlocksIngest() async {
        let model = await makeModel(keyStore: LockedKeyStore())
        XCTAssertEqual(model.status, .locked)
        await ingest(model, "x")
        XCTAssertTrue(model.items.isEmpty)
    }

    func testRecoveredStatusReported() async throws {
        let first = await makeModel()
        await ingest(first, "x")
        let other = await makeModel(keyStore: InMemoryKeyStore())
        guard case .recovered = other.status else { return XCTFail("expected recovered, got \(other.status)") }
        XCTAssertTrue(other.items.isEmpty)
    }

    func testPinnedAndRecentSections() async {
        let model = await makeModel()
        await ingest(model, "a", "b")
        await model.togglePin(model.results.first { $0.summary.previewText == "a" }!.id)
        XCTAssertEqual(model.pinnedResults.map(\.summary.previewText), ["a"])
        XCTAssertEqual(model.recentResults.map(\.summary.previewText), ["b"])
    }
}

struct LockedKeyStore: KeyStore {
    func loadKey() throws -> SymmetricKey? { throw KeyStoreError.unreadable(-25293) }
    func createKey() throws -> SymmetricKey { throw KeyStoreError.unreadable(-25293) }
    func deleteKey() throws { throw KeyStoreError.unreadable(-25293) }
}
