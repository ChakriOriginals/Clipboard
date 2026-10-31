/// What the app read from the pasteboard: allowlisted flavors with data, plus every type name
/// present (names only — used to detect concealed markers without reading their data).
public struct PasteboardSnapshot: Sendable {
    public let items: [[Representation]]
    public let types: Set<String>
    public let frontmostBundleID: String?
    public let frontmostAppName: String?

    public init(items: [[Representation]], types: Set<String>, frontmostBundleID: String?, frontmostAppName: String?) {
        self.items = items
        self.types = types
        self.frontmostBundleID = frontmostBundleID
        self.frontmostAppName = frontmostAppName
    }
}
