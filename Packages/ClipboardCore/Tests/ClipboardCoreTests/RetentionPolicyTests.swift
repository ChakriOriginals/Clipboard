import XCTest
@testable import ClipboardCore

final class RetentionPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    func testMaxAgeDeletesOldUnpinned() {
        let fresh = makeItem("fresh", lastCopied: ago(29 * day))
        let old = makeItem("old", lastCopied: ago(31 * day))
        let oldPinned = makeItem("pinned", lastCopied: ago(400 * day), pinned: true)
        let ids = RetentionPolicy.idsToDelete([fresh, old, oldPinned],
                                              settings: RetentionSettings(maxAge: 30 * day, maxCount: 1_000, sensitiveExpiry: nil), now: now)
        XCTAssertEqual(ids, [old.id])
    }

    func testMaxCountKeepsNewestUnpinned() {
        let items = (0..<5).map { makeItem("\($0)", lastCopied: ago(Double($0))) }
        let pinned = makeItem("p", lastCopied: ago(100), pinned: true)
        let ids = RetentionPolicy.idsToDelete(items + [pinned],
                                              settings: RetentionSettings(maxAge: nil, maxCount: 3, sensitiveExpiry: nil), now: now)
        XCTAssertEqual(Set(ids), [items[3].id, items[4].id])
    }

    func testSensitiveExpiry() {
        let recent = makeItem("s1", lastCopied: ago(30 * 60), sensitive: true)
        let expired = makeItem("s2", lastCopied: ago(61 * 60), sensitive: true)
        let pinned = makeItem("s3", lastCopied: ago(10 * day), pinned: true, sensitive: true)
        let normal = makeItem("n", lastCopied: ago(2 * 3600))
        let ids = RetentionPolicy.idsToDelete([recent, expired, pinned, normal],
                                              settings: RetentionSettings(maxAge: nil, maxCount: 1_000, sensitiveExpiry: 3600), now: now)
        XCTAssertEqual(ids, [expired.id])
    }

    func testForeverKeepsEverything() {
        let items = [makeItem("a", lastCopied: ago(10_000 * day)), makeItem("b", lastCopied: ago(1), sensitive: true)]
        XCTAssertEqual(RetentionPolicy.idsToDelete(items, settings: RetentionSettings(maxAge: nil, maxCount: 10_000, sensitiveExpiry: nil), now: now), [])
    }

    func testCountTrimDoesNotDoubleCountExpired() {
        let items = (0..<4).map { makeItem("\($0)", lastCopied: ago(Double($0) * day)) }
        let ids = RetentionPolicy.idsToDelete(items, settings: RetentionSettings(maxAge: 2.5 * day, maxCount: 2, sensitiveExpiry: nil), now: now)
        XCTAssertEqual(Set(ids), [items[2].id, items[3].id])
    }

    func testNegativeOrZeroMaxCountDoesNotTrap() {
        let items = (0..<3).map { makeItem("\($0)", lastCopied: ago(Double($0))) }
        XCTAssertEqual(RetentionPolicy.idsToDelete([], settings: RetentionSettings(maxAge: nil, maxCount: -1, sensitiveExpiry: nil), now: now), [])
        XCTAssertEqual(Set(RetentionPolicy.idsToDelete(items, settings: RetentionSettings(maxAge: nil, maxCount: -5, sensitiveExpiry: nil), now: now)),
                       Set(items.map(\.id)))
    }

    func testIsExpired() {
        let settings = RetentionSettings(maxAge: 30 * day, maxCount: 10, sensitiveExpiry: 600)
        XCTAssertTrue(RetentionPolicy.isExpired(makeItem("s", lastCopied: ago(601), sensitive: true), settings: settings, now: now))
        XCTAssertFalse(RetentionPolicy.isExpired(makeItem("s", lastCopied: ago(599), sensitive: true), settings: settings, now: now))
        XCTAssertFalse(RetentionPolicy.isExpired(makeItem("p", lastCopied: ago(601), pinned: true, sensitive: true), settings: settings, now: now))
        XCTAssertTrue(RetentionPolicy.isExpired(makeItem("o", lastCopied: ago(31 * day)), settings: settings, now: now))
        XCTAssertFalse(RetentionPolicy.isExpired(makeItem("n", lastCopied: ago(601)), settings: settings, now: now))
    }
}
