import Foundation

public struct RetentionSettings: Equatable, Sendable {
    /// nil = keep forever.
    public var maxAge: TimeInterval?
    public var maxCount: Int
    /// nil = sensitive items follow normal retention.
    public var sensitiveExpiry: TimeInterval?

    public init(maxAge: TimeInterval?, maxCount: Int, sensitiveExpiry: TimeInterval?) {
        self.maxAge = maxAge
        self.maxCount = maxCount
        self.sensitiveExpiry = sensitiveExpiry
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
        let limit = max(0, settings.maxCount)
        if survivors.count > limit {
            survivors.sort { $0.lastCopiedAt > $1.lastCopiedAt }
            doomed += survivors[limit...].map(\.id)
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
