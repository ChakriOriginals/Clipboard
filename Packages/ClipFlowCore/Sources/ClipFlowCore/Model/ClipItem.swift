import Foundation

/// A history entry as held in memory: plaintext metadata plus the decrypted summary.
public struct ClipItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var kind: ClipKind
    public let createdAt: Date
    public var lastCopiedAt: Date
    public let contentHash: Data
    public var isPinned: Bool
    public var isSensitive: Bool
    public let deviceID: String
    public let byteSize: Int
    public let hasThumbnail: Bool
    public let summary: ClipSummary

    /// What the UI may show: sensitive items are masked at display time; the real preview stays encrypted.
    public var displayPreview: String { isSensitive ? CapturePolicy.sensitivePreview : summary.previewText }

    public init(id: UUID, kind: ClipKind, createdAt: Date, lastCopiedAt: Date, contentHash: Data,
                isPinned: Bool, isSensitive: Bool, deviceID: String, byteSize: Int,
                hasThumbnail: Bool, summary: ClipSummary) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.contentHash = contentHash
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.deviceID = deviceID
        self.byteSize = byteSize
        self.hasThumbnail = hasThumbnail
        self.summary = summary
    }
}
