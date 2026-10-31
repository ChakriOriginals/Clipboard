import Foundation

/// A classified, policy-approved capture, ready to be encrypted and stored.
public struct ClipDraft: Sendable {
    public let kind: ClipKind
    public let previewText: String
    public let sourceAppBundleID: String?
    public let sourceAppName: String?
    public let fileNames: [String]
    public let isSensitive: Bool
    public let content: ClipContent
    /// Bytes that define identity for de-duplication (see SECURITY_MODEL §3).
    public let canonical: Data
    public let thumbnailPNG: Data?
    public let byteSize: Int

    public init(kind: ClipKind, previewText: String, sourceAppBundleID: String?, sourceAppName: String?,
                fileNames: [String], isSensitive: Bool, content: ClipContent, canonical: Data,
                thumbnailPNG: Data?, byteSize: Int) {
        self.kind = kind
        self.previewText = previewText
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.fileNames = fileNames
        self.isSensitive = isSensitive
        self.content = content
        self.canonical = canonical
        self.thumbnailPNG = thumbnailPNG
        self.byteSize = byteSize
    }
}
