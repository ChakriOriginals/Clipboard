import XCTest
@testable import ClipboardCore

final class SearchPerformanceTests: XCTestCase {
    func testSearch10kUnderTarget() {
        let words = ["swift", "clipboard", "apple", "notes", "meeting", "deploy", "invoice", "café", "release", "design"]
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let items = (0..<10_000).map { i -> ClipItem in
            let text = (0..<30).map { words[($0 * 7 + i) % words.count] }.joined(separator: " ") + " #\(i)"
            return makeItem(text, lastCopied: base.addingTimeInterval(Double(-i)))
        }
        let keys = Dictionary(uniqueKeysWithValues: items.map { ($0.id, SearchIndex.searchKey(for: $0)) })
        let query = SearchQuery(text: "deploy cafe #99", kind: .all, date: .any)

        var timings: [TimeInterval] = []
        for _ in 0..<5 {
            let start = DispatchTime.now()
            let results = SearchIndex.filter(items, keys: keys, query: query, now: base, calendar: .current)
            timings.append(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9)
            XCTAssertFalse(results.isEmpty)
        }
        let median = timings.sorted()[2]
        #if DEBUG
        let limit = 0.25
        #else
        let limit = 0.05 // PRODUCT_SPEC S3
        #endif
        XCTAssertLessThan(median, limit, "median \(median)s")
        print("Search 10k median: \(String(format: "%.1f", median * 1000)) ms")
    }
}
