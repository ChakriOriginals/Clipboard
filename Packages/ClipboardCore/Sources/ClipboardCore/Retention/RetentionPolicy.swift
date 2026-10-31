import Foundation

public struct RetentionSettings: Equatable, Sendable {
    /// nil = keep forever.
    public var maxAge: TimeInterval?
    public var maxCount: Int
    /// nil = sensitive items follow normal retention.
    public var sensitiveExpiry: TimeInterval?
    /// Total size of unpinned history. Each copy can be up to 100 MB, so a count limit alone would let one
    /// app grow history to item limit × 100 MB.
    public var maxTotalBytes: Int
    public static let defaultMaxTotalBytes = 2_000_000_000

    public init(maxAge: TimeInterval?, maxCount: Int, sensitiveExpiry: TimeInterval?,
                maxTotalBytes: Int = RetentionSettings.defaultMaxTotalBytes) {
        self.maxAge = maxAge
        self.maxCount = maxCount
        self.sensitiveExpiry = sensitiveExpiry
        self.maxTotalBytes = maxTotalBytes
    }
}

/// Which unpinned entries to delete. Pinned entries are always kept.
public enum RetentionPolicy {
    public static func idsToDelete(_ items: [ClipItem], settings: RetentionSettings, now: Date) -> [UUID] {
        var doomed: [UUID] = []
        var survivors: [ClipItem] = []
        for item in items where !item.isPinned {
            let age = now.timeIntervalSince(item.lastCopiedAt)
            if let maxAge = settings.maxAge, age > maxAge {
                doomed.append(item.id)
            } else if item.isSensitive, let expiry = settings.sensitiveExpiry, age > expiry {
                doomed.append(item.id)
            } else {
                survivors.append(item)
            }
        }
        // Keep the newest, up to the count limit and the size budget.
        survivors.sort { $0.lastCopiedAt > $1.lastCopiedAt }
        let limit = max(0, settings.maxCount)
        var total = 0
        for (index, item) in survivors.enumerated() {
            total += item.byteSize
            if index >= limit || total > settings.maxTotalBytes { doomed.append(item.id) }
        }
        return doomed
    }

    /// Age-based expiry for one item, so readers can hide expired items between sweeps.
    public static func isExpired(_ item: ClipItem, settings: RetentionSettings, now: Date) -> Bool {
        guard !item.isPinned else { return false }
        let age = now.timeIntervalSince(item.lastCopiedAt)
        if let maxAge = settings.maxAge, age > maxAge { return true }
        if item.isSensitive, let expiry = settings.sensitiveExpiry, age > expiry { return true }
        return false
    }
}
