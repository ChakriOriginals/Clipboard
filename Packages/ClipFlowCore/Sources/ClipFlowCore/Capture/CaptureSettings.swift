public enum SensitiveHandling: String, Codable, Sendable, CaseIterable {
    case maskAndExpire, dontSave
}

public struct CaptureSettings: Sendable, Equatable {
    public var isPaused: Bool
    public var excludedBundleIDs: Set<String>
    public var captureImages: Bool
    public var captureFiles: Bool
    public var sensitiveHandling: SensitiveHandling

    public init(isPaused: Bool, excludedBundleIDs: Set<String>, captureImages: Bool, captureFiles: Bool,
                sensitiveHandling: SensitiveHandling) {
        self.isPaused = isPaused
        self.excludedBundleIDs = excludedBundleIDs
        self.captureImages = captureImages
        self.captureFiles = captureFiles
        self.sensitiveHandling = sensitiveHandling
    }
}
