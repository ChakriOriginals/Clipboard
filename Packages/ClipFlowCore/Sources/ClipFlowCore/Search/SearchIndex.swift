import Foundation

/// In-memory filtering over decrypted summaries (content is encrypted, so SQL can't search it).
public enum SearchIndex {
    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .precomposedStringWithCanonicalMapping
    }

    /// Precompute once per item; sensitive items carry only their masked preview.
    public static func searchKey(for item: ClipItem) -> String {
        fold(([item.summary.previewText] + item.summary.fileNames).joined(separator: " "))
    }

    /// Matches when every whitespace-separated term occurs; ordered pinned first, then most recent.
    public static func filter(_ items: [ClipItem], keys: [UUID: String], query: SearchQuery, now: Date,
                              calendar: Calendar) -> [ClipItem] {
        let terms = fold(query.text).split(whereSeparator: \.isWhitespace).map(String.init)
        let earliest: Date? = switch query.date {
        case .any: nil
        case .today: calendar.startOfDay(for: now)
        case .last7Days: now.addingTimeInterval(-7 * 86_400)
        case .last30Days: now.addingTimeInterval(-30 * 86_400)
        }
        return items.filter { item in
            if let earliest, item.lastCopiedAt < earliest { return false }
            guard matches(item, kind: query.kind) else { return false }
            guard !terms.isEmpty else { return true }
            let key = keys[item.id] ?? searchKey(for: item)
            return terms.allSatisfy { containsBytes(key, $0) }
        }
        .sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.lastCopiedAt > b.lastCopiedAt
        }
    }

    /// Byte-level substring test. Valid because both sides are folded and NFC-normalized;
    /// ~10x faster than `String.contains`, which performs Unicode-aware comparison.
    static func containsBytes(_ haystack: String, _ needle: String) -> Bool {
        var haystack = haystack, needle = needle
        return haystack.withUTF8 { h in
            needle.withUTF8 { n in
                guard n.count <= h.count else { return false }
                guard let hb = h.baseAddress, let nb = n.baseAddress else { return n.isEmpty }
                return memmem(hb, h.count, nb, n.count) != nil
            }
        }
    }

    private static func matches(_ item: ClipItem, kind: KindFilter) -> Bool {
        switch kind {
        case .all: true
        case .pinned: item.isPinned
        case .text: item.kind == .text || item.kind == .richText
        case .urls: item.kind == .url
        case .code: item.kind == .code
        case .images: item.kind == .image
        case .files: item.kind == .file
        }
    }
}
