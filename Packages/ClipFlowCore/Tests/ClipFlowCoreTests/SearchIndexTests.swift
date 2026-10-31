import XCTest
@testable import ClipFlowCore

final class SearchIndexTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00 UTC
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func search(_ items: [ClipItem], _ text: String = "", kind: KindFilter = .all, date: DateFilter = .any) -> [ClipItem] {
        let keys = Dictionary(uniqueKeysWithValues: items.map { ($0.id, SearchIndex.searchKey(for: $0)) })
        return SearchIndex.filter(items, keys: keys, query: SearchQuery(text: text, kind: kind, date: date), now: now, calendar: calendar)
    }

    func testCaseAndDiacriticInsensitive() {
        let cafe = makeItem("Meet at the Café")
        let other = makeItem("nothing here")
        XCTAssertEqual(search([cafe, other], "CAFE").map(\.id), [cafe.id])
        XCTAssertEqual(search([cafe, other], "café").map(\.id), [cafe.id])
        let decomposed = "cafe\u{301}" // e + combining acute
        XCTAssertEqual(search([cafe, other], decomposed).map(\.id), [cafe.id])
    }

    func testAllTermsMustMatch() {
        let a = makeItem("swift concurrency notes")
        let b = makeItem("swift ui")
        XCTAssertEqual(search([a, b], "  swift   notes ").map(\.id), [a.id])
    }

    func testFileNamesAndURLsSearchable() {
        let file = makeItem("report.pdf", kind: .file, fileNames: ["report.pdf"])
        let url = makeItem("https://developer.apple.com/documentation", kind: .url)
        XCTAssertEqual(search([file, url], "report").map(\.id), [file.id])
        XCTAssertEqual(search([file, url], "apple.com/doc").map(\.id), [url.id])
    }

    func testEmojiAndCJK() {
        let item = makeItem("deploy 🚀 完了")
        XCTAssertEqual(search([item], "🚀").count, 1)
        XCTAssertEqual(search([item], "完了").count, 1)
    }

    func testSensitiveMatchedOnlyByMaskedLabel() {
        let secret = makeItem(CapturePolicy.sensitivePreview, sensitive: true)
        XCTAssertEqual(search([secret], "hunter2").count, 0)
        XCTAssertEqual(search([secret], "sensitive").count, 1)
    }

    func testKindFilters() {
        let text = makeItem("t"), rich = makeItem("r", kind: .richText), url = makeItem("u", kind: .url)
        let code = makeItem("c", kind: .code), image = makeItem("i", kind: .image), file = makeItem("f", kind: .file)
        let pinned = makeItem("p", pinned: true)
        let all = [text, rich, url, code, image, file, pinned]
        XCTAssertEqual(Set(search(all, kind: .text).map(\.id)), [text.id, rich.id, pinned.id])
        XCTAssertEqual(search(all, kind: .urls).map(\.id), [url.id])
        XCTAssertEqual(search(all, kind: .code).map(\.id), [code.id])
        XCTAssertEqual(search(all, kind: .images).map(\.id), [image.id])
        XCTAssertEqual(search(all, kind: .files).map(\.id), [file.id])
        XCTAssertEqual(search(all, kind: .pinned).map(\.id), [pinned.id])
        XCTAssertEqual(search(all).count, 7)
    }

    func testDateFilters() {
        let startOfToday = calendar.startOfDay(for: now)
        let today = makeItem("today", lastCopied: startOfToday)
        let yesterday = makeItem("yesterday", lastCopied: startOfToday.addingTimeInterval(-1))
        let sixDays = makeItem("6d", lastCopied: now.addingTimeInterval(-6 * 86_400))
        let eightDays = makeItem("8d", lastCopied: now.addingTimeInterval(-8 * 86_400))
        let fortyDays = makeItem("40d", lastCopied: now.addingTimeInterval(-40 * 86_400))
        let all = [today, yesterday, sixDays, eightDays, fortyDays]
        XCTAssertEqual(search(all, date: .today).map(\.id), [today.id])
        XCTAssertEqual(Set(search(all, date: .last7Days).map(\.id)), [today.id, yesterday.id, sixDays.id])
        XCTAssertEqual(Set(search(all, date: .last30Days).map(\.id)), [today.id, yesterday.id, sixDays.id, eightDays.id])
        XCTAssertEqual(search(all, date: .any).count, 5)
    }

    func testCombinedFilters() {
        let match = makeItem("swift code", kind: .code, lastCopied: now)
        let wrongKind = makeItem("swift text", lastCopied: now)
        let tooOld = makeItem("swift old", kind: .code, lastCopied: now.addingTimeInterval(-10 * 86_400))
        XCTAssertEqual(search([match, wrongKind, tooOld], "swift", kind: .code, date: .last7Days).map(\.id), [match.id])
    }

    func testOrderingPinnedFirstThenRecent() {
        let old = makeItem("old", lastCopied: now.addingTimeInterval(-100))
        let new = makeItem("new", lastCopied: now)
        let pinnedOld = makeItem("pin", lastCopied: now.addingTimeInterval(-1000), pinned: true)
        XCTAssertEqual(search([old, new, pinnedOld]).map(\.id), [pinnedOld.id, new.id, old.id])
    }
}
