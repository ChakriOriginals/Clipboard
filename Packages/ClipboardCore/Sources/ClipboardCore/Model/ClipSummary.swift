/// Small encrypted payload loaded for every entry, used for listing and search.
public struct ClipSummary: Codable, Sendable, Equatable {
    public let previewText: String
    public let sourceAppBundleID: String?
    public let sourceAppName: String?
    public let fileNames: [String]

    public init(previewText: String, sourceAppBundleID: String?, sourceAppName: String?, fileNames: [String]) {
        self.previewText = previewText
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.fileNames = fileNames
    }
}
